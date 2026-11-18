#import "RNTBBalancer.h"

#import <CoreText/CoreText.h>

#include <unordered_map>
#include <vector>

// Finite stand-in for measure's CGFLOAT_MAX height while counting and checking lines.
static const CGFloat kUnboundedHeight = 1e7;

// Which edge a narrowed line rect hugs inside the container's width: the text's alignment side, so
// the space balancing frees up falls on the side the text is ragged on anyway.
enum class RNTBSide { Left, Right, Centre };

struct RNTBLine {
  CGFloat width;
  RNTBSide side;
};

using RNTBLineMap = std::unordered_map<NSUInteger, RNTBLine>;

// Returns each planned line's width, keyed by the character index the line starts at. Lines it has
// no entry for (the last line of each paragraph, and every line of a stock paragraph) keep the full
// width. The container itself stays at RN's size, so the Yoga box and drawing frame are unchanged.
@interface RNTBPlanContainer : NSTextContainer
- (RNTBLineMap &)lines;
@end

@implementation RNTBPlanContainer {
  RNTBLineMap _lines;
}

- (RNTBLineMap &)lines
{
  return _lines;
}

- (BOOL)isSimpleRectangularTextContainer
{
  return NO;
}

- (CGRect)lineFragmentRectForProposedRect:(CGRect)proposedRect
                                  atIndex:(NSUInteger)characterIndex
                         writingDirection:(NSWritingDirection)baseWritingDirection
                            remainingRect:(CGRect *)remainingRect
{
  CGRect rect = [super lineFragmentRectForProposedRect:proposedRect
                                               atIndex:characterIndex
                                      writingDirection:baseWritingDirection
                                         remainingRect:remainingRect];
  auto it = _lines.find(characterIndex);
  if (it == _lines.end() || it->second.width >= rect.size.width) {
    return rect;
  }
  CGFloat width = it->second.width;
  switch (it->second.side) {
    case RNTBSide::Left:
      break;
    case RNTBSide::Right:
      rect.origin.x = CGRectGetMaxX(rect) - width;
      break;
    case RNTBSide::Centre:
      rect.origin.x += (rect.size.width - width) / 2;
      break;
  }
  rect.size.width = width;
  return rect;
}

@end

// A stock line: where it starts, and where its text sits in the container.
struct RNTBStockLine {
  NSUInteger start;
  CGRect used;
};

static std::vector<RNTBStockLine> layOut(NSLayoutManager *layoutManager, NSTextContainer *container)
{
  [layoutManager ensureLayoutForTextContainer:container];
  __block std::vector<RNTBStockLine> lines;
  NSRange glyphRange = [layoutManager glyphRangeForTextContainer:container];
  [layoutManager enumerateLineFragmentsForGlyphRange:glyphRange
                                          usingBlock:^(CGRect, CGRect used, NSTextContainer *, NSRange glyphs, BOOL *) {
                                            NSUInteger start = [layoutManager characterRangeForGlyphRange:glyphs
                                                                                         actualGlyphRange:NULL]
                                                                   .location;
                                            lines.push_back({start, used});
                                          }];
  return lines;
}

// One paragraph (text between hard line breaks) of the storage.
struct RNTBParagraph {
  NSRange full; // including its line terminator
  NSRange content; // without it
  std::vector<RNTBStockLine> stock; // its lines under stock wrapping
  bool planned = false;
  std::vector<NSUInteger> starts; // planned line starts (absolute)
  std::vector<std::pair<NSUInteger, CGFloat>> widths; // planned line start -> rect width, all but the last line
  RNTBSide side = RNTBSide::Left;
};

static bool isBreakSpace(unichar c)
{
  return c == ' ' || c == '\t' || c == 0x3000 || (c >= 0x2000 && c <= 0x200A && c != 0x2007);
}

// Where this paragraph's lines sit: from its alignment, its writing direction, or failing both
// (natural alignment and direction), from where its stock lines landed.
static RNTBSide sideOf(NSTextStorage *storage, const RNTBParagraph &p, CGFloat containerWidth)
{
  NSParagraphStyle *style = [storage attribute:NSParagraphStyleAttributeName atIndex:p.content.location effectiveRange:NULL];
  switch (style ? style.alignment : NSTextAlignmentNatural) {
    case NSTextAlignmentCenter:
      return RNTBSide::Centre;
    case NSTextAlignmentLeft:
      return RNTBSide::Left;
    case NSTextAlignmentRight:
      return RNTBSide::Right;
    default:
      break;
  }
  // RN sets no paragraph style when neither alignment nor direction is given; that's natural too.
  NSWritingDirection direction = style ? style.baseWritingDirection : NSWritingDirectionNatural;
  if (direction == NSWritingDirectionRightToLeft) {
    return RNTBSide::Right;
  }
  if (direction == NSWritingDirectionLeftToRight) {
    return RNTBSide::Left;
  }
  // Natural direction: the paragraph's raggedest stock line shows which edge the text hugs.
  CGFloat lean = 0;
  for (const RNTBStockLine &line : p.stock) {
    CGFloat gapLeft = CGRectGetMinX(line.used);
    CGFloat gapRight = containerWidth - CGRectGetMaxX(line.used);
    if (fabs(gapLeft - gapRight) > fabs(lean)) {
      lean = gapLeft - gapRight;
    }
  }
  return lean > 0.5 ? RNTBSide::Right : RNTBSide::Left;
}

// Plans the paragraph at its stock line count k: space-separated words as break points, widths from
// one CTLine, and the k-line split minimising Σ(U − wᵢ)² with no line wider than U. Returns false if
// no k-line plan fits.
static bool plan(NSTextStorage *storage, RNTBParagraph &p, CGFloat U, CGFloat padding)
{
  size_t k = p.stock.size();
  NSString *text = [storage.string substringWithRange:p.content];
  NSUInteger len = text.length;
  std::vector<unichar> chars(len);
  [text getCharacters:chars.data() range:NSMakeRange(0, len)];

  // Break points: word starts after a space, plus both ends.
  std::vector<NSUInteger> points{0};
  for (NSUInteger i = 1; i < len; i++) {
    if (isBreakSpace(chars[i - 1]) && !isBreakSpace(chars[i])) {
      points.push_back(i);
    }
  }
  points.push_back(len);
  size_t m = points.size() - 1; // words
  if (m < k) {
    return false;
  }

  // Glyph advances from one CTLine, attributed to string indices in logical order and prefix-summed,
  // so widths don't depend on the paragraph's direction (caret offsets jump about in RTL lines).
  CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)[storage attributedSubstringFromRange:p.content]);
  std::vector<CGFloat> prefix(len + 1, 0);
  CFArrayRef runs = CTLineGetGlyphRuns(line);
  std::vector<CGSize> advances;
  std::vector<CFIndex> indices;
  for (CFIndex r = 0; r < CFArrayGetCount(runs); r++) {
    CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
    CFIndex count = CTRunGetGlyphCount(run);
    advances.resize(count);
    indices.resize(count);
    CTRunGetAdvances(run, CFRangeMake(0, 0), advances.data());
    CTRunGetStringIndices(run, CFRangeMake(0, 0), indices.data());
    for (CFIndex g = 0; g < count; g++) {
      if (indices[g] >= 0 && (NSUInteger)indices[g] < len) {
        prefix[indices[g] + 1] += advances[g].width;
      }
    }
  }
  CFRelease(line);
  for (NSUInteger i = 0; i < len; i++) {
    prefix[i + 1] += prefix[i];
  }

  // x of each word's start, and of the end of the text before it with its spaces stripped.
  std::vector<CGFloat> xStart(m + 1), xEnd(m + 1);
  for (size_t j = 0; j <= m; j++) {
    NSUInteger end = points[j];
    while (end > 0 && isBreakSpace(chars[end - 1])) {
      end--;
    }
    xStart[j] = prefix[points[j]];
    xEnd[j] = prefix[end];
  }
  auto width = [&](size_t a, size_t b) { return MAX((CGFloat)0, xEnd[b] - xStart[a]); };

  const double kInfinity = 1e300;
  std::vector<std::vector<double>> cost(k + 1, std::vector<double>(m + 1, kInfinity));
  std::vector<std::vector<size_t>> from(k + 1, std::vector<size_t>(m + 1, 0));
  cost[0][0] = 0;
  for (size_t l = 1; l <= k; l++) {
    for (size_t j = l; j <= m; j++) {
      for (size_t i = l - 1; i < j; i++) {
        if (cost[l - 1][i] >= kInfinity) {
          continue;
        }
        CGFloat w = width(i, j);
        if (w > U + 0.5) {
          continue;
        }
        double c = cost[l - 1][i] + (U - w) * (U - w);
        if (c < cost[l][j]) {
          cost[l][j] = c;
          from[l][j] = i;
        }
      }
    }
  }
  if (cost[k][m] >= kInfinity) {
    return false;
  }

  std::vector<size_t> bounds(k + 1);
  bounds[k] = m;
  for (size_t l = k; l > 0; l--) {
    bounds[l - 1] = from[l][bounds[l]];
  }
  p.starts.clear();
  p.widths.clear();
  for (size_t l = 0; l < k; l++) {
    size_t a = bounds[l], b = bounds[l + 1];
    NSUInteger start = p.content.location + points[a];
    p.starts.push_back(start);
    if (b == m) {
      continue; // the last line keeps the full width
    }
    // Slack of half the gap to the next break point (1–4pt) absorbs rounding without letting the
    // next word fit.
    CGFloat w = width(a, b);
    CGFloat slack = MAX(1.0, MIN(4.0, (width(a, b + 1) - w) / 2));
    p.widths.push_back({start, MIN(U, w + slack) + 2 * padding});
  }
  return true;
}

// Line starts TextKit laid out inside `p`.
static std::vector<NSUInteger> startsIn(const std::vector<RNTBStockLine> &lines, const RNTBParagraph &p)
{
  std::vector<NSUInteger> starts;
  for (const RNTBStockLine &line : lines) {
    if (NSLocationInRange(line.start, p.full)) {
      starts.push_back(line.start);
    }
  }
  return starts;
}

static void fill(RNTBPlanContainer *container, const std::vector<RNTBParagraph> &paragraphs)
{
  [container lines].clear();
  for (const RNTBParagraph &p : paragraphs) {
    if (!p.planned) {
      continue;
    }
    for (const auto &w : p.widths) {
      [container lines][w.first] = {w.second, p.side};
    }
  }
}

void RNTBBalanceTextStorage(NSTextStorage *storage, NSUInteger maximumNumberOfLines)
{
  NSLayoutManager *layoutManager = storage.layoutManagers.firstObject;
  NSTextContainer *container = layoutManager.textContainers.firstObject;
  if (storage.length == 0 || layoutManager.textContainers.count != 1 || container == nil) {
    return;
  }
  CGSize size = container.size;
  if (!isfinite(size.width) || size.width <= 0 || size.width > 100000) {
    return;
  }

  // Count stock lines on RN's own (already font-scaled) stack, untruncated and unbounded in height,
  // so every line shows up and none is cut off.
  NSUInteger maxLines = container.maximumNumberOfLines;
  NSLineBreakMode mode = container.lineBreakMode;
  container.size = CGSizeMake(size.width, kUnboundedHeight);
  container.maximumNumberOfLines = 0;
  container.lineBreakMode = NSLineBreakByWordWrapping;
  auto restoreStock = [&]() {
    container.size = size;
    container.maximumNumberOfLines = maxLines;
    container.lineBreakMode = mode;
  };

  std::vector<RNTBStockLine> stock = layOut(layoutManager, container);
  if (maximumNumberOfLines > 0 && stock.size() > maximumNumberOfLines) {
    restoreStock(); // truncates: stock wrapping and stock ellipsis
    return;
  }

  // Group the stock lines by paragraph and plan each paragraph that wraps.
  NSString *string = storage.string;
  std::vector<RNTBParagraph> paragraphs;
  for (const RNTBStockLine &line : stock) {
    NSRange full = [string paragraphRangeForRange:NSMakeRange(line.start, 0)];
    if (paragraphs.empty() || !NSEqualRanges(paragraphs.back().full, full)) {
      RNTBParagraph p;
      p.full = full;
      p.content = full;
      while (p.content.length > 0 &&
             [[NSCharacterSet newlineCharacterSet] characterIsMember:[string characterAtIndex:NSMaxRange(p.content) - 1]]) {
        p.content.length--;
      }
      paragraphs.push_back(p);
    }
    paragraphs.back().stock.push_back(line);
  }

  CGFloat padding = container.lineFragmentPadding;
  CGFloat U = size.width - 2 * padding;
  bool anyPlanned = false;
  for (RNTBParagraph &p : paragraphs) {
    if (p.stock.size() > 1 && p.content.length > 0 && plan(storage, p, U, padding)) {
      p.planned = true;
      p.side = sideOf(storage, p, size.width);
      anyPlanned = true;
    }
  }
  if (!anyPlanned) {
    restoreStock();
    return;
  }

  // Impose the plan, then check that each planned paragraph's lines start where planned. Paragraphs
  // lay out independently (each starts on a fresh line), so a paragraph that doesn't hold drops back
  // to stock wrapping without moving the others; the second pass confirms that.
  RNTBPlanContainer *planContainer = [[RNTBPlanContainer alloc] initWithSize:container.size];
  planContainer.lineFragmentPadding = padding;
  planContainer.maximumNumberOfLines = 0;
  planContainer.lineBreakMode = NSLineBreakByWordWrapping;
  planContainer.exclusionPaths = container.exclusionPaths;
  fill(planContainer, paragraphs);
  [layoutManager removeTextContainerAtIndex:0];
  [layoutManager addTextContainer:planContainer];

  bool holds = false;
  for (int pass = 0; pass < 2 && !holds; pass++) {
    std::vector<RNTBStockLine> laidOut = layOut(layoutManager, planContainer);
    holds = true;
    anyPlanned = false;
    for (RNTBParagraph &p : paragraphs) {
      std::vector<NSUInteger> got = startsIn(laidOut, p);
      std::vector<NSUInteger> want = p.planned ? p.starts : startsIn(p.stock, p);
      if (got != want) {
        holds = false;
        p.planned = false;
      }
      anyPlanned = anyPlanned || p.planned;
    }
    if (!anyPlanned) {
      break;
    }
    if (!holds) {
      fill(planContainer, paragraphs);
      [layoutManager textContainerChangedGeometry:planContainer];
    }
  }

  if (!holds || !anyPlanned) {
    // Give RN back its own container: exactly stock.
    [layoutManager removeTextContainerAtIndex:0];
    [layoutManager addTextContainer:container];
    restoreStock();
    return;
  }

  planContainer.size = size;
  planContainer.maximumNumberOfLines = maxLines;
  planContainer.lineBreakMode = mode;
}
