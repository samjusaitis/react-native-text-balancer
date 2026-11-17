// PROTOTYPE (tickets 04 + 06, iOS balance injection spike). Throwaway, do not ship as-is.
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

#import <react/renderer/attributedstring/ParagraphAttributes.h>

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

static NSUInteger gCalls = 0;
static double gTotalMs = 0;

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

  CGFloat inset = 0;
  if (!truncated && target > 1) {
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

  container.size = savedSize;
  container.maximumNumberOfLines = savedMaxLines;
  container.lineBreakMode = savedMode;
  container.exclusionPaths = inset > 0.5 ? strips(W, inset, side) : @[];

  double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
  gCalls++;
  gTotalMs += ms;
  os_log(
      OS_LOG_DEFAULT,
      "[TextBalancer prototype] w=%.1f h=%.1f lines=%lu maxLines=%lu truncated=%d side=%ld scaled=%d inset=%.1f %.2fms (avg %.2fms over %lu calls)",
      W,
      size.height,
      (unsigned long)target,
      (unsigned long)maxLines,
      truncated,
      (long)side,
      paragraphAttributes.adjustsFontSizeToFit,
      inset,
      ms,
      gTotalMs / gCalls,
      (unsigned long)gCalls);
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
