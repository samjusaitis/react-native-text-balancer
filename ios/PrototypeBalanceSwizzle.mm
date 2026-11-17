// PROTOTYPE (tickets 04 + 06 + 08, iOS balance injection spike). Throwaway, do not ship as-is.
//
// Ticket 08 adds a second mode, MINIMUM RAGGEDNESS, flagged per Text by
// android_hyphenationFrequency="full" (Android-only prop, parsed on iOS, otherwise ignored).
// Per paragraph: keep the full-width line count k, measure word-boundary x offsets once with a
// one-line CTLine, pick the k-line break plan minimising sum((U - w_i)^2) (= line-width
// variance), then impose it with an NSTextContainer subclass that returns a per-line fragment
// width keyed by the line's start character index. The resulting breaks are verified against
// the plan; on mismatch it falls back to the squeeze.
//
// Question (06): does narrowing with NSTextContainer.exclusionPaths, applied after RN's
// scaleFontSizeToFitSize:, fix 04's trade-offs (press highlight overflowing to the box edge,
// no adjustsFontSizeToFit) while measure, draw, hit-test and onTextLayout still agree?
//
// Approach: every one of those paths builds its TextKit 1 stack through the private
// -[RCTTextLayoutManager _textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:].
// We swizzle it. When paragraphAttributes.textBreakStrategy == Balanced (the existing,
// Android-only prop, which is still parsed into ParagraphAttributes on iOS), we call the
// original first (so any font scaling has already happened), then binary-search the
// narrowest exclusion strip on RN's own container that keeps the full-width line count.
// The strip sits on the trailing side (left for right-aligned / RTL text), or half on each
// side for centred text. The container (and so the Yoga box) stays full width, like CSS
// `text-wrap: balance`; the line fragment rects shrink, so selection/highlight rects do too.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>

#import <CoreText/CoreText.h>
#import <react/renderer/attributedstring/ParagraphAttributes.h>

#include <vector>

using facebook::react::HyphenationFrequency;
using facebook::react::ParagraphAttributes;
using facebook::react::TextBreakStrategy;

typedef NSTextStorage *(*BuildIMP)(id, SEL, NSAttributedString *, ParagraphAttributes, CGSize);
static BuildIMP gOriginal = nullptr;

static const CGFloat kStripHeight = 1e7; // finite stand-in for measure's CGFLOAT_MAX height

typedef NS_ENUM(NSInteger, StripSide) { StripRight, StripLeft, StripBoth };

static NSArray<UIBezierPath *> *strips(CGFloat width, CGFloat inset, StripSide side)
{
  if (inset <= 0) {
    return @[];
  }
  switch (side) {
    case StripRight:
      return @[ [UIBezierPath bezierPathWithRect:CGRectMake(width - inset, 0, inset, kStripHeight)] ];
    case StripLeft:
      return @[ [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, inset, kStripHeight)] ];
    case StripBoth:
      return @[
        [UIBezierPath bezierPathWithRect:CGRectMake(0, 0, inset / 2, kStripHeight)],
        [UIBezierPath bezierPathWithRect:CGRectMake(width - inset / 2, 0, inset / 2, kStripHeight)],
      ];
  }
}

static NSUInteger countLines(NSLayoutManager *layoutManager, NSTextContainer *container, CGRect *outShortest)
{
  [layoutManager ensureLayoutForTextContainer:container];
  __block NSUInteger lines = 0;
  __block CGRect shortest = CGRectNull;
  NSRange glyphRange = [layoutManager glyphRangeForTextContainer:container];
  [layoutManager enumerateLineFragmentsForGlyphRange:glyphRange
                                          usingBlock:^(CGRect, CGRect usedRect, NSTextContainer *, NSRange, BOOL *) {
                                            lines++;
                                            if (CGRectIsNull(shortest) || usedRect.size.width < shortest.size.width) {
                                              shortest = usedRect;
                                            }
                                          }];
  if (outShortest) {
    *outShortest = shortest;
  }
  return lines;
}


// ---- Ticket 08: minimum-raggedness plan -------------------------------------------------

@interface TBPlanContainer : NSTextContainer
@property (nonatomic, copy) NSDictionary<NSNumber *, NSNumber *> *lineWidths; // line start char -> fragment width
@property (nonatomic) NSInteger side;
@end

@implementation TBPlanContainer
- (BOOL)isSimpleRectangularTextContainer
{
  return NO;
}
- (CGRect)lineFragmentRectForProposedRect:(CGRect)proposedRect
                                  atIndex:(NSUInteger)characterIndex
                         writingDirection:(NSWritingDirection)baseWritingDirection
                            remainingRect:(CGRect *)remainingRect
{
  CGRect r = [super lineFragmentRectForProposedRect:proposedRect
                                            atIndex:characterIndex
                                   writingDirection:baseWritingDirection
                                      remainingRect:remainingRect];
  NSNumber *w = self.lineWidths[@(characterIndex)];
  if (w == nil || w.doubleValue >= r.size.width) {
    return r;
  }
  CGFloat nw = w.doubleValue;
  switch (self.side) {
    case StripLeft:
      r.origin.x = CGRectGetMaxX(r) - nw;
      break;
    case StripBoth:
      r.origin.x += (r.size.width - nw) / 2;
      break;
    default:
      break;
  }
  r.size.width = nw;
  return r;
}
@end

static BOOL isBreakSpace(unichar c)
{
  return c == ' ' || c == '\t' || c == 0x3000 || (c >= 0x2000 && c <= 0x200A && c != 0x2007);
}

// Plans one paragraph's breaks into `widths` (keyed by absolute line-start index) and appends the
// planned line starts to `starts`. Returns NO if no k-line plan fits.
static BOOL planParagraph(
    NSAttributedString *storage,
    NSRange content,
    NSUInteger k,
    CGFloat U,
    CGFloat padding,
    NSMutableDictionary<NSNumber *, NSNumber *> *widths,
    NSMutableArray<NSNumber *> *starts)
{
  NSString *text = [storage.string substringWithRange:content];
  NSUInteger len = text.length;
  std::vector<NSUInteger> pts{0};
  for (NSUInteger i = 1; i < len; i++) {
    if (isBreakSpace([text characterAtIndex:i - 1]) && !isBreakSpace([text characterAtIndex:i])) {
      pts.push_back(i);
    }
  }
  pts.push_back(len);
  size_t m = pts.size() - 1; // number of words
  if (m < k) {
    return NO;
  }

  CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)[storage attributedSubstringFromRange:content]);
  std::vector<CGFloat> xStart(m + 1), xEnd(m + 1);
  for (size_t j = 0; j <= m; j++) {
    NSUInteger e = pts[j];
    while (e > 0 && isBreakSpace([text characterAtIndex:e - 1])) {
      e--;
    }
    xStart[j] = CTLineGetOffsetForStringIndex(line, pts[j], NULL);
    xEnd[j] = CTLineGetOffsetForStringIndex(line, e, NULL);
  }
  CFRelease(line);
  auto width = [&](size_t a, size_t b) { return (CGFloat)fabs(xEnd[b] - xStart[a]); };

  const double INF = 1e300;
  std::vector<std::vector<double>> dp(k + 1, std::vector<double>(m + 1, INF));
  std::vector<std::vector<size_t>> from(k + 1, std::vector<size_t>(m + 1, 0));
  dp[0][0] = 0;
  for (size_t l = 1; l <= k; l++) {
    for (size_t j = l; j <= m; j++) {
      for (size_t i = l - 1; i < j; i++) {
        if (dp[l - 1][i] >= INF) {
          continue;
        }
        CGFloat w = width(i, j);
        if (w > U + 0.5) {
          continue;
        }
        double c = dp[l - 1][i] + (U - w) * (U - w);
        if (c < dp[l][j]) {
          dp[l][j] = c;
          from[l][j] = i;
        }
      }
    }
  }
  if (dp[k][m] >= INF) {
    return NO;
  }
  std::vector<size_t> bounds(k + 1);
  bounds[k] = m;
  for (size_t l = k; l > 0; l--) {
    bounds[l - 1] = from[l][bounds[l]];
  }
  for (size_t l = 0; l < k; l++) {
    size_t a = bounds[l], b = bounds[l + 1];
    NSUInteger start = content.location + pts[a];
    [starts addObject:@(start)];
    if (b == m) {
      continue; // last line: full width
    }
    CGFloat w = width(a, b);
    CGFloat withNext = width(a, b + 1);
    CGFloat slack = MAX(1.0, MIN(4.0, (withNext - w) / 2));
    widths[@(start)] = @(MIN(U, w + slack) + 2 * padding);
  }
  return YES;
}

static NSArray<NSNumber *> *lineStarts(NSLayoutManager *layoutManager, NSTextContainer *container)
{
  [layoutManager ensureLayoutForTextContainer:container];
  NSMutableArray<NSNumber *> *starts = [NSMutableArray new];
  NSRange glyphRange = [layoutManager glyphRangeForTextContainer:container];
  [layoutManager enumerateLineFragmentsForGlyphRange:glyphRange
                                          usingBlock:^(CGRect, CGRect, NSTextContainer *, NSRange g, BOOL *) {
                                            [starts addObject:@([layoutManager characterRangeForGlyphRange:g
                                                                                          actualGlyphRange:NULL]
                                                                    .location)];
                                          }];
  return starts;
}

// Swaps in a TBPlanContainer imposing a min-raggedness plan. Expects `container` in counting
// configuration (W x 1e7, unlimited lines). Returns the new container, or nil on failure (RN's
// container is then back in place). `outInfo` gets a short description for the log.
static NSTextContainer *applyMinRaggedness(
    NSTextStorage *storage,
    NSLayoutManager *layoutManager,
    NSTextContainer *container,
    StripSide side,
    NSString **outInfo)
{
  NSArray<NSNumber *> *fullStarts = lineStarts(layoutManager, container);
  NSString *string = storage.string;
  CGFloat padding = container.lineFragmentPadding;
  CGFloat U = container.size.width - 2 * padding;

  // Group full-width lines by paragraph.
  NSMutableArray<NSValue *> *paragraphs = [NSMutableArray new];
  NSMutableArray<NSNumber *> *counts = [NSMutableArray new];
  for (NSNumber *s in fullStarts) {
    NSRange p = [string paragraphRangeForRange:NSMakeRange(s.unsignedIntegerValue, 0)];
    if (paragraphs.count > 0 && NSEqualRanges(paragraphs.lastObject.rangeValue, p)) {
      counts[counts.count - 1] = @(counts.lastObject.unsignedIntegerValue + 1);
    } else {
      [paragraphs addObject:[NSValue valueWithRange:p]];
      [counts addObject:@1];
    }
  }

  NSMutableDictionary<NSNumber *, NSNumber *> *widths = [NSMutableDictionary new];
  NSMutableArray<NSNumber *> *planStarts = [NSMutableArray new];
  NSMutableString *info = [NSMutableString new];
  for (NSUInteger p = 0; p < paragraphs.count; p++) {
    NSRange r = paragraphs[p].rangeValue;
    NSUInteger k = counts[p].unsignedIntegerValue;
    while (r.length > 0 && [[NSCharacterSet newlineCharacterSet] characterIsMember:[string characterAtIndex:NSMaxRange(r) - 1]]) {
      r.length--;
    }
    [info appendFormat:@"%@%lu", p ? @"," : @"", (unsigned long)k];
    if (k <= 1 || !planParagraph(storage, r, k, U, padding, widths, planStarts)) {
      // Unplanned paragraph: keep its full-width breaks.
      for (NSNumber *s in fullStarts) {
        NSUInteger v = s.unsignedIntegerValue;
        if (v >= paragraphs[p].rangeValue.location && v < NSMaxRange(paragraphs[p].rangeValue)) {
          [planStarts addObject:s];
        }
      }
      if (k > 1) {
        [info appendString:@"!"]; // plan infeasible
      }
    }
  }

  TBPlanContainer *plan = [[TBPlanContainer alloc] initWithSize:container.size];
  plan.lineFragmentPadding = padding;
  plan.maximumNumberOfLines = 0;
  plan.lineBreakMode = NSLineBreakByWordWrapping;
  plan.lineWidths = widths;
  plan.side = side;
  [layoutManager removeTextContainerAtIndex:0];
  [layoutManager addTextContainer:plan];

  NSArray<NSNumber *> *got = lineStarts(layoutManager, plan);
  *outInfo = [NSString stringWithFormat:@"paras=[%@] planned=%lu", info, (unsigned long)widths.count];
  if (![got isEqualToArray:planStarts]) {
    *outInfo = [*outInfo stringByAppendingFormat:@" MISMATCH got=%@ want=%@",
                                                 [got componentsJoinedByString:@" "],
                                                 [planStarts componentsJoinedByString:@" "]];
    [layoutManager removeTextContainerAtIndex:0];
    [layoutManager addTextContainer:container];
    return nil;
  }
  return plan;
}

// -------------------------------------------------------------------------------------------

static NSUInteger gCalls[2] = {0, 0};
static double gTotalMs[2] = {0, 0};

static NSTextStorage *balancedBuild(
    id self,
    SEL _cmd,
    NSAttributedString *string,
    ParagraphAttributes paragraphAttributes,
    CGSize size)
{
  NSTextStorage *storage = gOriginal(self, _cmd, string, paragraphAttributes, size);
  if (paragraphAttributes.textBreakStrategy != TextBreakStrategy::Balanced || storage.length == 0 ||
      !isfinite(size.width) || size.width <= 0 || size.width > 100000) {
    return storage;
  }

  CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
  NSLayoutManager *layoutManager = storage.layoutManagers.firstObject;
  NSTextContainer *container = layoutManager.textContainers.firstObject;
  CGFloat W = size.width;

  // Count on RN's own stack (already font-scaled), but untruncated and unbounded in height,
  // so a narrower strip shows up as an extra line rather than as truncation or clipping.
  CGSize savedSize = container.size;
  NSUInteger savedMaxLines = container.maximumNumberOfLines;
  NSLineBreakMode savedMode = container.lineBreakMode;
  container.size = CGSizeMake(W, kStripHeight);
  container.maximumNumberOfLines = 0;
  container.lineBreakMode = NSLineBreakByWordWrapping;

  CGRect shortest;
  NSUInteger target = countLines(layoutManager, container, &shortest);
  NSUInteger maxLines = paragraphAttributes.maximumNumberOfLines;
  BOOL truncated = maxLines > 0 && target > maxLines;

  // Which side the strip goes on: explicit centre → both; otherwise look at where the
  // shortest full-width line sits (covers right alignment and RTL natural alignment).
  NSParagraphStyle *style = [storage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:nil];
  StripSide side = StripRight;
  if (style.alignment == NSTextAlignmentCenter) {
    side = StripBoth;
  } else if (!CGRectIsNull(shortest) && CGRectGetMinX(shortest) > W - CGRectGetMaxX(shortest) + 0.5) {
    side = StripLeft;
  }

  BOOL minRag = paragraphAttributes.android_hyphenationFrequency == HyphenationFrequency::Full;
  NSString *planInfo = @"-";
  if (minRag && !truncated && target > 1) {
    NSString *info = nil;
    NSTextContainer *plan = applyMinRaggedness(storage, layoutManager, container, side, &info);
    planInfo = info;
    if (plan != nil) {
      plan.size = savedSize;
      plan.maximumNumberOfLines = savedMaxLines;
      plan.lineBreakMode = savedMode;
      container = nil;
    }
  }

  CGFloat inset = 0;
  if (container != nil && !truncated && target > 1) {
    CGFloat lo = 0, hi = W - W / target; // inset range; lines can't average narrower than W/target
    while (hi - lo > 0.5) {
      CGFloat mid = (lo + hi) / 2;
      container.exclusionPaths = strips(W, mid, side);
      if (countLines(layoutManager, container, nullptr) <= target) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    inset = lo;
  }

  if (container != nil) {
    container.size = savedSize;
    container.maximumNumberOfLines = savedMaxLines;
    container.lineBreakMode = savedMode;
    container.exclusionPaths = inset > 0.5 ? strips(W, inset, side) : @[];
  }

  double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
  int mode = minRag ? 1 : 0;
  gCalls[mode]++;
  gTotalMs[mode] += ms;
  os_log(
      OS_LOG_DEFAULT,
      "[TextBalancer prototype] mode=%{public}s w=%.1f h=%.1f lines=%lu maxLines=%lu truncated=%d side=%ld scaled=%d inset=%.1f plan=%{public}@ %.3fms (avg %.3fms over %lu calls)",
      minRag ? "minrag" : "squeeze",
      W,
      size.height,
      (unsigned long)target,
      (unsigned long)maxLines,
      truncated,
      (long)side,
      paragraphAttributes.adjustsFontSizeToFit,
      inset,
      planInfo,
      ms,
      gTotalMs[mode] / gCalls[mode],
      (unsigned long)gCalls[mode]);
  return storage;
}

@interface PrototypeTextBalancerSwizzle : NSObject
@end

@implementation PrototypeTextBalancerSwizzle

+ (void)load
{
  Class cls = NSClassFromString(@"RCTTextLayoutManager");
  SEL sel = NSSelectorFromString(@"_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:");
  Method method = cls ? class_getInstanceMethod(cls, sel) : nullptr;
  if (method == nullptr) {
    os_log_error(OS_LOG_DEFAULT, "[TextBalancer prototype] RCTTextLayoutManager hook not found");
    return;
  }
  gOriginal = (BuildIMP)method_setImplementation(method, (IMP)balancedBuild);
  os_log(OS_LOG_DEFAULT, "[TextBalancer prototype] swizzled RCTTextLayoutManager (exclusionPaths)");
}

@end
