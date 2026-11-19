#import "RNTBBalancer.h"

#import <CoreText/CoreText.h>

#include <algorithm>
#include <memory>
#include <unordered_map>
#include <vector>

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
// The map is immutable, so a cache hit shares it with the cached RNTBBalancedBreaks.
@interface RNTBLineWidthContainer : NSTextContainer
- (void)setLines:(std::shared_ptr<const RNTBLineMap>)lines;
@end

@implementation RNTBLineWidthContainer {
  std::shared_ptr<const RNTBLineMap> _lines;
}

- (instancetype)initWithSize:(CGSize)size
{
  if (self = [super initWithSize:size]) {
    _lines = std::make_shared<const RNTBLineMap>();
  }
  return self;
}

- (void)setLines:(std::shared_ptr<const RNTBLineMap>)lines
{
  _lines = std::move(lines);
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
  auto it = _lines->find(characterIndex);
  if (it == _lines->end() || it->second.width >= rect.size.width) {
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
static std::vector<RNTBLaidOutLine> layOut(
    NSLayoutManager *layoutManager,
    NSTextContainer *container,
    bool *complete = nullptr)
{
  [layoutManager ensureLayoutForTextContainer:container];
  __block std::vector<RNTBLaidOutLine> lines;
  NSRange glyphRange = [layoutManager glyphRangeForTextContainer:container];
  [layoutManager
      enumerateLineFragmentsForGlyphRange:glyphRange
                               usingBlock:^(CGRect rect, CGRect used, NSTextContainer *, NSRange glyphs, BOOL *) {
                                 NSRange characters = [layoutManager characterRangeForGlyphRange:glyphs
                                                                                actualGlyphRange:NULL];
                                 lines.push_back({characters.location, rect, used});
                               }];
  if (complete != nullptr) {
    *complete = NSMaxRange(glyphRange) >= layoutManager.numberOfGlyphs;
  }
  return lines;
}

// One paragraph of the storage: the text between hard line breaks (newlines, U+2029 and U+2028).
// Parts split by U+2028 share their paragraph style.
struct RNTBParagraph {
  NSRange full; // including its line terminator
  NSRange content; // without it
  std::vector<RNTBLaidOutLine> defaultLines; // its lines under default wrapping
  bool balanced = false;
  bool repaired = false; // has had its one repair retry
  std::vector<NSUInteger> breaks; // balanced breaks: the line starts chosen (absolute)
  std::vector<std::pair<NSUInteger, CGFloat>> widths; // balanced line start -> rect width, all but the last line
  RNTBSide side = RNTBSide::Left;

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
  NSParagraphStyle *style =
      [storage attribute:NSParagraphStyleAttributeName atIndex:p.content.location effectiveRange:NULL];
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
static bool chooseBreaks(RNTBParagraph &p, CGFloat U)
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
    p.widths.push_back({start, MIN(U, w + slack)});
  }
  return true;
}

// The one repair retry: at the first line start where TextKit disagreed with the balanced breaks,
// drop the chosen candidate, take TextKit's break as a candidate instead, and choose again.
static bool repair(RNTBParagraph &p, const std::vector<NSUInteger> &got, CGFloat U)
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
  return chooseBreaks(p, U);
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

// Sets the balanced paragraphs' line widths on the container, and returns them.
static std::shared_ptr<const RNTBLineMap> fill(
    RNTBLineWidthContainer *container,
    const std::vector<RNTBParagraph> &paragraphs)
{
  auto lines = std::make_shared<RNTBLineMap>();
  for (const RNTBParagraph &p : paragraphs) {
    if (!p.balanced) {
      continue;
    }
    for (const auto &w : p.widths) {
      (*lines)[w.first] = {w.second, p.side};
    }
  }
  [container setLines:lines];
  return lines;
}

@interface RNTBBalancedBreaks ()
- (instancetype)initWithLines:(std::shared_ptr<const RNTBLineMap>)lines minimumHeight:(CGFloat)minimumHeight;
- (const std::shared_ptr<const RNTBLineMap> &)lines;
@end

@implementation RNTBBalancedBreaks {
  std::shared_ptr<const RNTBLineMap> _lines;
}

+ (RNTBBalancedBreaks *)defaultWrapping
{
  static RNTBBalancedBreaks *defaultWrapping =
      [[RNTBBalancedBreaks alloc] initWithLines:std::make_shared<const RNTBLineMap>() minimumHeight:0];
  return defaultWrapping;
}

- (instancetype)initWithLines:(std::shared_ptr<const RNTBLineMap>)lines minimumHeight:(CGFloat)minimumHeight
{
  if (self = [super init]) {
    _lines = std::move(lines);
    _minimumHeight = minimumHeight;
  }
  return self;
}

- (const std::shared_ptr<const RNTBLineMap> &)lines
{
  return _lines;
}

@end

// Whether TextKit clipped the last line of a complete layout, the line starting at glyph `lastLine`.
// Without a line limit RN's container clips: when its height cuts the text off, TextKit puts the
// rest of the last paragraph into the last line there's room for and hides the glyphs past the
// edge. That layout counts as complete and not truncated, but the height changed it. The line's
// used rect and glyph bounds stop at the edge, so look for the hidden glyphs instead: outside
// clipping, TextKit only hides null glyphs (ligature parts, a truncated line's tail) and control
// characters (newlines, tabs, soft hyphens, U+2060, attachments).
static bool clipsLastLine(NSLayoutManager *layoutManager, NSUInteger lastLine)
{
  for (NSUInteger g = lastLine; g < layoutManager.numberOfGlyphs; g++) {
    if ([layoutManager notShownAttributeForGlyphAtIndex:g] &&
        !([layoutManager propertyForGlyphAtIndex:g] & (NSGlyphPropertyNull | NSGlyphPropertyControlCharacter))) {
      return true;
    }
  }
  return false;
}

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
  return widthContainer;
}

RNTBBalancedBreaks *RNTBBalanceTextStorage(NSTextStorage *storage)
{
  NSLayoutManager *layoutManager;
  NSTextContainer *container;
  if (!stackOf(storage, &layoutManager, &container)) {
    return RNTBBalancedBreaks.defaultWrapping;
  }
  CGSize size = container.size;

  // The plan comes from RN's own layout: RN's container exactly as RN built it, so its lines are
  // default wrapping, and when the outcome is default wrapping, RN's container goes back already
  // laid out. Lines cut off, truncated or clipped there stay as RN laid them out.
  bool complete;
  std::vector<RNTBLaidOutLine> defaultLines = layOut(layoutManager, container, &complete);
  // A truncating or clipping line break mode can put the rest of the text into the last line, so
  // check that line too, as RN's processTruncatedAttributedText does.
  bool truncated = false;
  if (!defaultLines.empty()) {
    NSUInteger lastLine = [layoutManager glyphIndexForCharacterAtIndex:defaultLines.back().start];
    truncated = [layoutManager truncatedGlyphRangeInLineFragmentForGlyphAtIndex:lastLine].location != NSNotFound ||
        (complete && clipsLastLine(layoutManager, lastLine));
  }
  if (!complete || truncated) {
    NSUInteger maximumNumberOfLines = container.maximumNumberOfLines;
    if (maximumNumberOfLines > 0 && defaultLines.size() >= maximumNumberOfLines) {
      return RNTBBalancedBreaks.defaultWrapping; // truncates: default wrapping and the default ellipsis
    }
    // RN's height cut lines off or clipped the last one, so the outcome depends on that height,
    // which the break cache doesn't key on (only on the width): not reusable.
    return nil;
  }

  // Group the default lines by paragraph and choose balanced breaks for each paragraph that wraps.
  // A paragraph here ends at any hard line break, a line separator (U+2028) included: TextKit
  // always breaks there, so each part balances on its own, as with \n.
  NSString *string = storage.string;
  std::vector<RNTBParagraph> paragraphs;
  for (const RNTBLaidOutLine &line : defaultLines) {
    NSUInteger start, end, contentsEnd;
    [string getLineStart:&start end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(line.start, 0)];
    NSRange full = NSMakeRange(start, end - start);
    if (paragraphs.empty() || !NSEqualRanges(paragraphs.back().full, full)) {
      RNTBParagraph p;
      p.full = full;
      p.content = NSMakeRange(start, contentsEnd - start);
      paragraphs.push_back(p);
    }
    paragraphs.back().defaultLines.push_back(line);
  }

  CGFloat U = size.width; // RN's builder sets lineFragmentPadding to 0, so lines get the full width
  bool anyBalanced = false;
  for (RNTBParagraph &p : paragraphs) {
    if (p.defaultLines.size() <= 1 || p.content.length == 0) {
      continue;
    }
    if ([string rangeOfString:@"\t" options:NSLiteralSearch range:p.content].location != NSNotFound) {
      continue; // a tab's width depends on where it lands: default wrapping
    }
    NSParagraphStyle *style =
        [storage attribute:NSParagraphStyleAttributeName atIndex:p.content.location effectiveRange:NULL];
    if (style.alignment == NSTextAlignmentJustified) {
      continue; // narrowed lines can't be justified to the full width: default wrapping
    }
    gatherInputs(storage, p);
    if (chooseBreaks(p, U)) {
      p.balanced = true;
      p.side = sideOf(storage, p, size.width);
      anyBalanced = true;
    }
  }
  if (!anyBalanced) {
    return RNTBBalancedBreaks.defaultWrapping; // RN's container, already laid out
  }

  // Impose the balanced breaks through a width container at RN's geometry, then check that each
  // balanced paragraph's lines start at its breaks and every other paragraph's at its default
  // starts. RN's container is never changed, so giving it back is exactly default wrapping (RN
  // then lays it out again). Paragraphs lay out independently (each starts on a fresh line), so a
  // paragraph changing its breaks doesn't move the others; the next pass confirms it. A balanced
  // paragraph that doesn't hold gets one repair retry, then drops back to default wrapping, so each
  // paragraph changes at most twice and the loop ends. Past four passes, it settles for default wrapping.
  RNTBLineWidthContainer *widthContainer = widthContainerLike(container, size);
  std::shared_ptr<const RNTBLineMap> lines = fill(widthContainer, paragraphs);
  [layoutManager removeTextContainerAtIndex:0];
  [layoutManager addTextContainer:widthContainer];
  auto restoreDefault = [&]() {
    [layoutManager removeTextContainerAtIndex:0];
    [layoutManager addTextContainer:container];
  };

  for (int pass = 0; pass < 4; pass++) {
    std::vector<RNTBLaidOutLine> laidOut = layOut(layoutManager, widthContainer, &complete);
    if (!complete) {
      restoreDefault();
      return nil; // RN's height cut lines off, as above
    }
    bool holds = true;
    anyBalanced = false;
    for (RNTBParagraph &p : paragraphs) {
      std::vector<NSUInteger> got = startsIn(laidOut, p);
      std::vector<NSUInteger> want = p.balanced ? p.breaks : startsIn(p.defaultLines, p);
      if (got != want) {
        if (!p.balanced) {
          restoreDefault(); // another pass would lay it out the same: default wrapping
          return RNTBBalancedBreaks.defaultWrapping;
        }
        holds = false;
        if (!p.repaired) {
          p.repaired = true;
          p.balanced = repair(p, got, U);
        } else {
          p.balanced = false;
        }
      }
      anyBalanced = anyBalanced || p.balanced;
    }
    if (holds) {
      return [[RNTBBalancedBreaks alloc] initWithLines:lines minimumHeight:CGRectGetMaxY(laidOut.back().rect)];
    }
    if (!anyBalanced) {
      break;
    }
    // The line widths aren't geometry TextKit watches, so invalidate the layout explicitly.
    lines = fill(widthContainer, paragraphs);
    [layoutManager textContainerChangedGeometry:widthContainer];
  }
  restoreDefault(); // RN's own container: exactly default wrapping
  return RNTBBalancedBreaks.defaultWrapping;
}

void RNTBApplyBalancedBreaks(NSTextStorage *storage, RNTBBalancedBreaks *breaks)
{
  NSLayoutManager *layoutManager;
  NSTextContainer *container;
  if ([breaks lines]->empty() || !stackOf(storage, &layoutManager, &container)) {
    return; // default wrapping: RN's own stack as it is
  }
  RNTBLineWidthContainer *widthContainer = widthContainerLike(container, container.size);
  [widthContainer setLines:[breaks lines]];
  [layoutManager removeTextContainerAtIndex:0];
  [layoutManager addTextContainer:widthContainer];
}
