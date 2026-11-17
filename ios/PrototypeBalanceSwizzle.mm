// PROTOTYPE (ticket 04, iOS tailIndent injection spike). Throwaway, do not ship as-is.
//
// Question: can a balanced wrap width be injected into RN Fabric's iOS Text so that
// measure, draw, hit-test and onTextLayout all agree, without forking RN?
//
// Approach: every one of those paths builds its TextKit 1 stack through the private
// -[RCTTextLayoutManager _textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:].
// We swizzle it. When paragraphAttributes.textBreakStrategy == Balanced (the existing,
// Android-only prop, which is still parsed into ParagraphAttributes on iOS), we
// binary-search the narrowest width that keeps the full-width line count, then apply the
// difference as a negative NSParagraphStyle.tailIndent on the returned storage. The text
// container (and so the Yoga box) stays full width, like CSS `text-wrap: balance`.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>

#import <react/renderer/attributedstring/ParagraphAttributes.h>

using facebook::react::ParagraphAttributes;
using facebook::react::TextBreakStrategy;

typedef NSTextStorage *(*BuildIMP)(id, SEL, NSAttributedString *, ParagraphAttributes, CGSize);
static BuildIMP gOriginal = nullptr;

static NSUInteger lineCount(NSAttributedString *string, CGFloat width)
{
  NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(width, CGFLOAT_MAX)];
  container.lineFragmentPadding = 0;
  NSLayoutManager *layoutManager = [NSLayoutManager new];
  layoutManager.usesFontLeading = NO;
  [layoutManager addTextContainer:container];
  NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:string];
  [storage addLayoutManager:layoutManager];
  [layoutManager ensureLayoutForTextContainer:container];

  __block NSUInteger lines = 0;
  NSRange glyphRange = [layoutManager glyphRangeForTextContainer:container];
  [layoutManager enumerateLineFragmentsForGlyphRange:glyphRange
                                          usingBlock:^(CGRect, CGRect, NSTextContainer *, NSRange, BOOL *) {
                                            lines++;
                                          }];
  return lines;
}

// Narrowest width (0.5pt precision) that keeps the same line count as `width`.
static CGFloat balancedWidth(NSAttributedString *string, CGFloat width, NSUInteger *outLines)
{
  NSUInteger target = lineCount(string, width);
  *outLines = target;
  if (target <= 1) {
    return width;
  }
  CGFloat lo = width / target, hi = width; // lines can't fit narrower than width/target on average
  while (hi - lo > 0.5) {
    CGFloat mid = (lo + hi) / 2;
    if (lineCount(string, mid) <= target) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return hi;
}

static void applyInset(NSTextStorage *storage, CGFloat inset)
{
  NSRange full = NSMakeRange(0, storage.length);
  NSMutableArray *edits = [NSMutableArray new];
  [storage enumerateAttribute:NSParagraphStyleAttributeName
                      inRange:full
                      options:0
                   usingBlock:^(NSParagraphStyle *style, NSRange range, BOOL *) {
                     NSMutableParagraphStyle *ps =
                         style ? [style mutableCopy] : [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
                     if (ps.alignment == NSTextAlignmentCenter) {
                       // Split the inset so centred lines stay centred in the full box.
                       ps.headIndent += inset / 2;
                       ps.firstLineHeadIndent += inset / 2;
                       ps.tailIndent = -inset / 2;
                     } else {
                       ps.tailIndent = -inset;
                     }
                     [edits addObject:@[ [NSValue valueWithRange:range], ps ]];
                   }];
  [storage beginEditing];
  for (NSArray *edit in edits) {
    [storage addAttribute:NSParagraphStyleAttributeName value:edit[1] range:[edit[0] rangeValue]];
  }
  [storage endEditing];
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
  if (paragraphAttributes.textBreakStrategy != TextBreakStrategy::Balanced || paragraphAttributes.adjustsFontSizeToFit ||
      storage.length == 0 || !isfinite(size.width) || size.width <= 0 || size.width > 100000) {
    return storage;
  }

  CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
  NSUInteger lines = 0;
  CGFloat width = balancedWidth(storage, size.width, &lines);
  CGFloat inset = size.width - width;
  if (inset > 0.5) {
    applyInset(storage, inset);
  }
  double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
  gCalls++;
  gTotalMs += ms;
  os_log(
      OS_LOG_DEFAULT,
      "[TextBalancer prototype] w=%.1f lines=%lu balanced=%.1f inset=%.1f %.2fms (avg %.2fms over %lu calls)",
      size.width,
      (unsigned long)lines,
      width,
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
  os_log(OS_LOG_DEFAULT, "[TextBalancer prototype] swizzled RCTTextLayoutManager");
}

@end
