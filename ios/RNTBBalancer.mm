#import "RNTBBalancer.h"

#import <CoreText/CoreText.h>

#include <algorithm>
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

// Returns each balanced line's width, keyed by the character index the line starts at. Lines it has
// no entry for (the last line of each paragraph, and every line of a default-wrapping paragraph) keep the full
// width. The container itself stays at RN's size, so the Yoga box and drawing frame are unchanged.
@interface RNTBLineWidthContainer : NSTextContainer
- (RNTBLineMap &)lines;
@end

@implementation RNTBLineWidthContainer {
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

// A laid-out line: where it starts, its line fragment, and where its text sits in it.
struct RNTBLaidOutLine {
  NSUInteger start;
  CGRect rect;
  CGRect used;
};

// Lays the storage out in `container` and returns its lines. `complete` says whether every glyph
// found room; it's false when the container's height or line limit cut lines off.
static std::vector<RNTBLaidOutLine> layOut(NSLayoutManager *layoutManager, NSTextContainer *container, bool *complete = nullptr)
{
  [layoutManager ensureLayoutForTextContainer:container];
  __block std::vector<RNTBLaidOutLine> lines;
  NSRange glyphRange = [layoutManager glyphRangeForTextContainer:container];
  [layoutManager enumerateLineFragmentsForGlyphRange:glyphRange
                                          usingBlock:^(CGRect rect, CGRect used, NSTextContainer *, NSRange glyphs, BOOL *) {
                                            NSUInteger start = [layoutManager characterRangeForGlyphRange:glyphs
                                                                                         actualGlyphRange:NULL]
                                                                   .location;
                                            lines.push_back({start, rect, used});
                                          }];
  if (complete != nullptr) {
    *complete = NSMaxRange(glyphRange) >= layoutManager.numberOfGlyphs;
  }
  return lines;
}

// One paragraph (text between hard line breaks) of the storage.
struct RNTBParagraph {
  NSRange full; // including its line terminator
  NSRange content; // without it
  std::vector<RNTBLaidOutLine> defaultLines; // its lines under default wrapping
  bool balanced = false;
  bool repaired = false; // has had its one repair retry
  std::vector<NSUInteger> breaks; // balanced breaks: the line starts chosen (absolute)
  std::vector<std::pair<NSUInteger, CGFloat>> widths; // balanced line start -> rect width, all but the last line
  RNTBSide side = RNTBSide::Left;
  // Paragraph style runs whose lineBreakStrategy has pushOut, with their original style, and
  // whether pushOut is currently cleared from them in the storage.
  std::vector<std::pair<NSRange, NSParagraphStyle *>> pushOutStyles;
  bool pushOutCleared = false;

  // Inputs to chooseBreaks, relative to `content`.
  std::vector<unichar> chars;
  std::vector<CGFloat> prefix; // logical-order advance sum before each index
  std::vector<NSUInteger> candidates; // possible line starts, sorted, including 0 and the length
  NSAttributedString *text = nil; // the content's attributed substring
};

static bool isBreakSpace(unichar c)
{
  return c == ' ' || c == '\t' || c == 0x3000 || (c >= 0x2000 && c <= 0x200A && c != 0x2007);
}

static bool isHangul(unichar c)
{
  return (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F);
}

// Where this paragraph's lines sit: from its alignment, its writing direction, or failing both
// (natural alignment and direction), from where its default lines landed.
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
  // Natural direction: the paragraph's raggedest default line shows which edge the text hugs.
  CGFloat lean = 0;
  for (const RNTBLaidOutLine &line : p.defaultLines) {
    CGFloat gapLeft = CGRectGetMinX(line.used);
    CGFloat gapRight = containerWidth - CGRectGetMaxX(line.used);
    if (fabs(gapLeft - gapRight) > fabs(lean)) {
      lean = gapLeft - gapRight;
    }
  }
  return lean > 0.5 ? RNTBSide::Right : RNTBSide::Left;
}

// Break candidates and widths for the paragraph.
//
// Candidates are CFStringTokenizer line-break units (UAX #14: spaces, hyphens, soft hyphens, CJK
// with kinsoku, dictionary breaks for Thai), plus both sides of each inline attachment (U+FFFC).
// Under hangul-word priority, breaks between two Hangul characters are dropped.
//
// Widths are glyph advances from one CTLine, attributed to string indices in logical order and
// prefix-summed, so they don't depend on the paragraph's direction (caret offsets jump about in
// bidi lines). An attachment takes its `bounds` width, which Core Text doesn't see.
static void gatherInputs(NSTextStorage *storage, RNTBParagraph &p)
{
  p.text = [storage attributedSubstringFromRange:p.content];
  NSString *string = p.text.string;
  NSUInteger len = string.length;
  p.chars.resize(len);
  [string getCharacters:p.chars.data() range:NSMakeRange(0, len)];

  std::vector<NSUInteger> &c = p.candidates;
  c.assign(1, 0);
  CFStringTokenizerRef tokenizer =
      CFStringTokenizerCreate(NULL, (CFStringRef)string, CFRangeMake(0, len), kCFStringTokenizerUnitLineBreak, NULL);
  while (CFStringTokenizerAdvanceToNextToken(tokenizer) != kCFStringTokenizerTokenNone) {
    CFIndex at = CFStringTokenizerGetCurrentTokenRange(tokenizer).location;
    if (at > 0 && (NSUInteger)at < len) {
      c.push_back(at);
    }
  }
  CFRelease(tokenizer);
  for (NSUInteger i = 0; i < len; i++) {
    if (p.chars[i] == 0xFFFC) {
      if (i > 0) {
        c.push_back(i);
      }
      if (i + 1 < len) {
        c.push_back(i + 1);
      }
    }
  }
  c.push_back(len);
  std::sort(c.begin(), c.end());
  c.erase(std::unique(c.begin(), c.end()), c.end());
  NSParagraphStyle *style = [p.text attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
  if (style.lineBreakStrategy & NSLineBreakStrategyHangulWordPriority) {
    c.erase(std::remove_if(c.begin() + 1,
                           c.end() - 1,
                           [&](NSUInteger i) { return isHangul(p.chars[i - 1]) && isHangul(p.chars[i]); }),
            c.end() - 1);
  }

  std::vector<CGFloat> advance(len, 0);
  CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)p.text);
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
        advance[indices[g]] += advances[g].width;
      }
    }
  }
  CFRelease(line);
  for (NSUInteger i = 0; i < len; i++) {
    if (p.chars[i] == 0xFFFC) {
      NSTextAttachment *attachment = [p.text attribute:NSAttachmentAttributeName atIndex:i effectiveRange:NULL];
      if (attachment != nil) {
        advance[i] = attachment.bounds.size.width;
      }
    }
  }
  p.prefix.assign(len + 1, 0);
  for (NSUInteger i = 0; i < len; i++) {
    p.prefix[i + 1] = p.prefix[i] + advance[i];
  }
}

// Advance of the '-' TextKit draws when it breaks at the soft hyphen at relative index `i`.
static CGFloat hyphenAdvance(const RNTBParagraph &p, NSUInteger i)
{
  UIFont *font = [p.text attribute:NSFontAttributeName atIndex:i effectiveRange:NULL];
  if (font == nil) {
    return 0;
  }
  UniChar hyphen = '-';
  CGGlyph glyph;
  if (!CTFontGetGlyphsForCharacters((__bridge CTFontRef)font, &hyphen, &glyph, 1)) {
    return 0;
  }
  return CTFontGetAdvancesForGlyphs((__bridge CTFontRef)font, kCTFontOrientationHorizontal, &glyph, NULL, 1);
}

// Chooses the paragraph's balanced breaks at its default line count k: the k-line split of its
// candidates minimising Σ(U − wᵢ)² with no line wider than U. Returns false if no k-line split fits.
static bool chooseBreaks(RNTBParagraph &p, CGFloat U, CGFloat padding)
{
  size_t k = p.defaultLines.size();
  const std::vector<NSUInteger> &c = p.candidates;
  size_t m = c.size() - 1; // segments
  if (m < k) {
    return false;
  }
  NSUInteger len = p.chars.size();

  // x of each candidate's start, and of the end of a line broken there: trailing whitespace
  // stripped, plus the '-' TextKit draws at a soft hyphen.
  std::vector<CGFloat> xStart(m + 1), xEnd(m + 1);
  for (size_t j = 0; j <= m; j++) {
    NSUInteger end = c[j];
    while (end > 0 && isBreakSpace(p.chars[end - 1])) {
      end--;
    }
    xStart[j] = p.prefix[c[j]];
    xEnd[j] = p.prefix[end];
    if (c[j] > 0 && c[j] < len && p.chars[c[j] - 1] == 0x00AD) {
      xEnd[j] += hyphenAdvance(p, c[j] - 1);
    }
  }
  auto width = [&](size_t a, size_t b) { return MAX((CGFloat)0, xEnd[b] - xStart[a]); };

  // Windowed: for each line end j, scan line starts i leftwards only while the line still fits, so
  // CJK's one candidate per character costs O(k·m·c) for c candidates per line, not O(k·m²).
  const double kInfinity = 1e300;
  std::vector<double> cost((k + 1) * (m + 1), kInfinity);
  std::vector<uint32_t> from((k + 1) * (m + 1), 0);
  auto at = [&](size_t l, size_t j) { return l * (m + 1) + j; };
  cost[at(0, 0)] = 0;
  for (size_t l = 1; l <= k; l++) {
    for (size_t j = l; j <= m; j++) {
      double best = kInfinity;
      size_t bestFrom = 0;
      for (size_t i = j; i-- > l - 1;) {
        CGFloat w = width(i, j);
        if (w > U + 0.5) {
          break; // lines only get wider as i moves left
        }
        double before = cost[at(l - 1, i)];
        if (before >= kInfinity) {
          continue;
        }
        double total = before + (U - w) * (U - w);
        if (total < best) {
          best = total;
          bestFrom = i;
        }
      }
      cost[at(l, j)] = best;
      from[at(l, j)] = (uint32_t)bestFrom;
    }
  }
  if (cost[at(k, m)] >= kInfinity) {
    return false;
  }

  std::vector<size_t> bounds(k + 1);
  bounds[k] = m;
  for (size_t l = k; l > 0; l--) {
    bounds[l - 1] = from[at(l, bounds[l])];
  }
  p.breaks.clear();
  p.widths.clear();
  for (size_t l = 0; l < k; l++) {
    size_t a = bounds[l], b = bounds[l + 1];
    NSUInteger start = p.content.location + c[a];
    p.breaks.push_back(start);
    if (b == m) {
      continue; // the last line keeps the full width
    }
    // Slack of half the gap to the next break point (1–4pt) absorbs rounding without letting the
    // next segment fit.
    CGFloat w = width(a, b);
    CGFloat slack = MAX(1.0, MIN(4.0, (width(a, b + 1) - w) / 2));
    p.widths.push_back({start, MIN(U, w + slack) + 2 * padding});
  }
  return true;
}

// The one repair retry: at the first line start where TextKit disagreed with the balanced breaks,
// drop the chosen candidate, take TextKit's break as a candidate instead, and choose again.
static bool repair(RNTBParagraph &p, const std::vector<NSUInteger> &got, CGFloat U, CGFloat padding)
{
  size_t d = 0;
  while (d < got.size() && d < p.breaks.size() && got[d] == p.breaks[d]) {
    d++;
  }
  NSUInteger first = p.content.location, last = NSMaxRange(p.content);
  std::vector<NSUInteger> &c = p.candidates;
  if (d < p.breaks.size() && p.breaks[d] > first && p.breaks[d] < last) {
    c.erase(std::remove(c.begin(), c.end(), p.breaks[d] - first), c.end());
  }
  if (d < got.size() && got[d] > first && got[d] < last) {
    c.insert(std::lower_bound(c.begin(), c.end(), got[d] - first), got[d] - first);
    c.erase(std::unique(c.begin(), c.end()), c.end());
  }
  return chooseBreaks(p, U, padding);
}

// Line starts TextKit laid out inside `p`.
static std::vector<NSUInteger> startsIn(const std::vector<RNTBLaidOutLine> &lines, const RNTBParagraph &p)
{
  std::vector<NSUInteger> starts;
  for (const RNTBLaidOutLine &line : lines) {
    if (NSLocationInRange(line.start, p.full)) {
      starts.push_back(line.start);
    }
  }
  return starts;
}

static NSParagraphStyle *withoutPushOut(NSParagraphStyle *style)
{
  NSMutableParagraphStyle *cleared = [style mutableCopy];
  cleared.lineBreakStrategy = style.lineBreakStrategy & NSLineBreakStrategyHangulWordPriority;
  return cleared;
}

// The push-out rule: while checked balanced breaks are applied to a paragraph, pushOut is cleared
// from its lineBreakStrategy, because it fights them; `standard` becomes hangul-word only. A paragraph
// on default wrapping has its original style. TextKit 1 ignores pushOut in RN today, so this keeps
// the user's setting for when it doesn't, rather than changing what's drawn now.
static void findPushOut(NSTextStorage *storage, RNTBParagraph &p)
{
  [storage enumerateAttribute:NSParagraphStyleAttributeName
                      inRange:p.content
                      options:0
                   usingBlock:^(NSParagraphStyle *style, NSRange range, BOOL *) {
                     if (style != nil && (style.lineBreakStrategy & NSLineBreakStrategyPushOut)) {
                       p.pushOutStyles.push_back({range, style});
                     }
                   }];
}

// Brings each paragraph's style in line with its state: pushOut cleared on balanced paragraphs,
// the original style back on the rest. With `allDefault` (the whole storage back on default
// wrapping), every original style comes back.
static void syncPushOut(NSTextStorage *storage, std::vector<RNTBParagraph> &paragraphs, bool allDefault)
{
  bool changed = false;
  for (RNTBParagraph &p : paragraphs) {
    bool clear = p.balanced && !allDefault;
    if (p.pushOutStyles.empty() || clear == p.pushOutCleared) {
      continue;
    }
    if (!changed) {
      [storage beginEditing];
      changed = true;
    }
    for (const auto &run : p.pushOutStyles) {
      [storage addAttribute:NSParagraphStyleAttributeName
                      value:clear ? withoutPushOut(run.second) : run.second
                      range:run.first];
    }
    p.pushOutCleared = clear;
  }
  if (changed) {
    [storage endEditing];
  }
}

static void fill(RNTBLineWidthContainer *container, const std::vector<RNTBParagraph> &paragraphs)
{
  [container lines].clear();
  for (const RNTBParagraph &p : paragraphs) {
    if (!p.balanced) {
      continue;
    }
    for (const auto &w : p.widths) {
      [container lines][w.first] = {w.second, p.side};
    }
  }
}

@interface RNTBBalancedBreaks ()
- (instancetype)initWithLines:(RNTBLineMap)lines
                  pushOutRuns:(std::vector<NSRange>)pushOutRuns
                minimumHeight:(CGFloat)minimumHeight;
- (const RNTBLineMap &)lines;
- (const std::vector<NSRange> &)pushOutRuns;
@end

@implementation RNTBBalancedBreaks {
  RNTBLineMap _lines;
  std::vector<NSRange> _pushOutRuns;
}

+ (RNTBBalancedBreaks *)defaultWrapping
{
  static RNTBBalancedBreaks *defaultWrapping = [[RNTBBalancedBreaks alloc] initWithLines:RNTBLineMap() pushOutRuns:std::vector<NSRange>() minimumHeight:0];
  return defaultWrapping;
}

- (instancetype)initWithLines:(RNTBLineMap)lines
                  pushOutRuns:(std::vector<NSRange>)pushOutRuns
                minimumHeight:(CGFloat)minimumHeight
{
  if (self = [super init]) {
    _lines = std::move(lines);
    _pushOutRuns = std::move(pushOutRuns);
    _minimumHeight = minimumHeight;
  }
  return self;
}

- (const RNTBLineMap &)lines
{
  return _lines;
}

- (const std::vector<NSRange> &)pushOutRuns
{
  return _pushOutRuns;
}

@end

// The storage's one layout manager and text container, as RN's stack builder returns them, if the
// container has a width the hook can balance in.
static bool stackOf(NSTextStorage *storage, NSLayoutManager **layoutManager, NSTextContainer **container)
{
  *layoutManager = storage.layoutManagers.firstObject;
  *container = (*layoutManager).textContainers.firstObject;
  if (storage.length == 0 || (*layoutManager).textContainers.count != 1 || *container == nil) {
    return false;
  }
  CGFloat width = (*container).size.width;
  return isfinite(width) && width > 0 && width <= 100000;
}

// A width container with RN's container's configuration, except its size.
static RNTBLineWidthContainer *widthContainerLike(NSTextContainer *container, CGSize size)
{
  RNTBLineWidthContainer *widthContainer = [[RNTBLineWidthContainer alloc] initWithSize:size];
  widthContainer.lineFragmentPadding = container.lineFragmentPadding;
  widthContainer.maximumNumberOfLines = container.maximumNumberOfLines;
  widthContainer.lineBreakMode = container.lineBreakMode;
  widthContainer.exclusionPaths = container.exclusionPaths;
  return widthContainer;
}

RNTBBalancedBreaks *RNTBBalanceTextStorage(NSTextStorage *storage, NSUInteger maximumNumberOfLines)
{
  NSLayoutManager *layoutManager;
  NSTextContainer *container;
  if (!stackOf(storage, &layoutManager, &container)) {
    return RNTBBalancedBreaks.defaultWrapping;
  }
  CGSize size = container.size;

  // All the work happens in our own container; RN's is never changed, so giving it back is exactly
  // default wrapping. Every change to a container's geometry makes TextKit lay the whole storage out again,
  // so the width container changes geometry once: from counting to RN's, before the check. (Moving
  // RN's container to the counting geometry and back cost two extra layouts per build.)
  //
  // First, count default lines (the width container with no line widths lays out as RN's does),
  // untruncated and unbounded in height, so every line shows up and none is cut off.
  CGFloat padding = container.lineFragmentPadding;
  RNTBLineWidthContainer *widthContainer =
      widthContainerLike(container, CGSizeMake(size.width, MAX(size.height, kUnboundedHeight)));
  widthContainer.maximumNumberOfLines = 0;
  widthContainer.lineBreakMode = container.maximumNumberOfLines == 0 ? container.lineBreakMode : NSLineBreakByWordWrapping;
  [layoutManager removeTextContainerAtIndex:0];
  [layoutManager addTextContainer:widthContainer];
  auto restoreDefault = [&]() {
    [layoutManager removeTextContainerAtIndex:0];
    [layoutManager addTextContainer:container];
  };

  std::vector<RNTBLaidOutLine> defaultLines = layOut(layoutManager, widthContainer);
  if (maximumNumberOfLines > 0 && defaultLines.size() > maximumNumberOfLines) {
    restoreDefault(); // truncates: default wrapping and the default ellipsis
    return RNTBBalancedBreaks.defaultWrapping;
  }

  // Group the default lines by paragraph and choose balanced breaks for each paragraph that wraps.
  NSString *string = storage.string;
  std::vector<RNTBParagraph> paragraphs;
  for (const RNTBLaidOutLine &line : defaultLines) {
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
    paragraphs.back().defaultLines.push_back(line);
  }

  CGFloat U = size.width - 2 * padding;
  bool anyBalanced = false;
  for (RNTBParagraph &p : paragraphs) {
    if (p.defaultLines.size() <= 1 || p.content.length == 0) {
      continue;
    }
    if ([string rangeOfString:@"\t" options:NSLiteralSearch range:p.content].location != NSNotFound) {
      continue; // a tab's width depends on where it lands: default wrapping
    }
    gatherInputs(storage, p);
    if (chooseBreaks(p, U, padding)) {
      p.balanced = true;
      p.side = sideOf(storage, p, size.width);
      findPushOut(storage, p);
      anyBalanced = true;
    }
  }
  if (!anyBalanced) {
    restoreDefault();
    return RNTBBalancedBreaks.defaultWrapping;
  }

  // Impose the balanced breaks at RN's geometry, then check that each balanced paragraph's lines
  // start at its breaks. A paragraph that doesn't hold gets one repair retry, then drops back to default
  // wrapping. Paragraphs lay out independently (each starts on a fresh line), so that doesn't move
  // the others; the next pass confirms it. If RN's height cuts lines off, nothing holds: default wrapping.
  // Setting a geometry that hasn't changed (measure's height is already unbounded) doesn't
  // invalidate the layout, and nor do the line widths, so invalidate it explicitly.
  syncPushOut(storage, paragraphs, false);
  fill(widthContainer, paragraphs);
  widthContainer.size = size;
  widthContainer.maximumNumberOfLines = container.maximumNumberOfLines;
  widthContainer.lineBreakMode = container.lineBreakMode;
  [layoutManager textContainerChangedGeometry:widthContainer];

  bool holds = false;
  bool cut = false; // RN's height (or line limit) cut lines off in some pass
  CGFloat bottom = 0;
  for (int pass = 0; pass < 4 && !holds; pass++) {
    bool complete;
    std::vector<RNTBLaidOutLine> laidOut = layOut(layoutManager, widthContainer, &complete);
    cut = cut || !complete;
    bottom = laidOut.empty() ? 0 : CGRectGetMaxY(laidOut.back().rect);
    holds = true;
    anyBalanced = false;
    for (RNTBParagraph &p : paragraphs) {
      std::vector<NSUInteger> got = startsIn(laidOut, p);
      std::vector<NSUInteger> want = p.balanced ? p.breaks : startsIn(p.defaultLines, p);
      if (got != want) {
        holds = false;
        if (p.balanced && !p.repaired) {
          p.repaired = true;
          p.balanced = repair(p, got, U, padding);
        } else {
          p.balanced = false;
        }
      }
      anyBalanced = anyBalanced || p.balanced;
    }
    if (!anyBalanced) {
      break;
    }
    if (!holds) {
      syncPushOut(storage, paragraphs, false);
      fill(widthContainer, paragraphs);
      [layoutManager textContainerChangedGeometry:widthContainer];
    }
  }

  if (!holds || !anyBalanced) {
    syncPushOut(storage, paragraphs, true);
    restoreDefault(); // RN's own container and styles: exactly default wrapping
  }
  // Lines cut off by RN's height make the outcome depend on that height, which the break cache
  // doesn't key on (only on the width), so it isn't reusable.
  if (cut) {
    return nil;
  }
  if (!holds || !anyBalanced) {
    return RNTBBalancedBreaks.defaultWrapping;
  }
  std::vector<NSRange> pushOutRuns;
  for (const RNTBParagraph &p : paragraphs) {
    if (p.balanced) {
      for (const auto &run : p.pushOutStyles) {
        pushOutRuns.push_back(run.first);
      }
    }
  }
  return [[RNTBBalancedBreaks alloc] initWithLines:[widthContainer lines] pushOutRuns:pushOutRuns minimumHeight:bottom];
}

void RNTBApplyBalancedBreaks(NSTextStorage *storage, RNTBBalancedBreaks *breaks)
{
  NSLayoutManager *layoutManager;
  NSTextContainer *container;
  if ([breaks lines].empty() || !stackOf(storage, &layoutManager, &container)) {
    return; // default wrapping: RN's own stack as it is
  }
  if (![breaks pushOutRuns].empty()) {
    [storage beginEditing];
    for (NSRange run : [breaks pushOutRuns]) {
      NSParagraphStyle *style = [storage attribute:NSParagraphStyleAttributeName atIndex:run.location effectiveRange:NULL];
      [storage addAttribute:NSParagraphStyleAttributeName value:withoutPushOut(style) range:run];
    }
    [storage endEditing];
  }
  RNTBLineWidthContainer *widthContainer = widthContainerLike(container, container.size);
  [widthContainer lines] = [breaks lines];
  [layoutManager removeTextContainerAtIndex:0];
  [layoutManager addTextContainer:widthContainer];
}
