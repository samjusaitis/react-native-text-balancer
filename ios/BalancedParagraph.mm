// PROTOTYPE (ticket 10): iOS balancing via the library's own Fabric paragraph component. Throwaway.
//
// Question: does a codegen host component `BalancedParagraph`, built from subclasses of RN's
// paragraph classes, balance end to end while RN's own <Text> stays untouched (no swizzle)?
//
//   BalancedParagraphShadowNode      : ParagraphShadowNode   (hides Name()/Handle() -> "BalancedParagraph")
//   BalancedTextLayoutManager        : TextLayoutManager     (swaps protected nativeTextLayoutManager_)
//   RCTBalancedTextLayoutManager     : RCTTextLayoutManager  (overrides the private stack builder; calls
//                                                             super, then imposes the ticket 08 plan)
//   BalancedParagraphComponentDescriptor (own TextLayoutManager instance -> own measure cache)
//   RCTBalancedParagraphComponentView : RCTParagraphComponentView (registered via codegenConfig)
//
// Min-raggedness code below is ported verbatim from ticket 08 (PrototypeBalanceSwizzle.mm), minus the
// squeeze: on a plan mismatch RN's container is put back (stock wrapping).
//
// Prototype-only debug hooks:
//   - launch arg `-TBSimulateMissingSelector YES` makes the runtime guard look for a bogus selector
//     (simulates RN renaming the private builder).
//   - `xcrun simctl spawn <udid> notifyutil -p tb.dumpa11y` dumps every paragraph view's accessibility
//     elements to os_log (stock Paragraph and BalancedParagraph side by side).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <os/log.h>

#import <CoreText/CoreText.h>

#import <React/RCTLog.h>
#import <React/RCTParagraphComponentView.h>
#import <react/renderer/components/text/ParagraphShadowNode.h>
#import <react/renderer/core/ConcreteComponentDescriptor.h>
#import <react/renderer/textlayoutmanager/RCTTextLayoutManager.h>
#import <react/renderer/textlayoutmanager/TextLayoutManager.h>
#import <react/utils/ManagedObjectWrapper.h>

#include <algorithm>
#include <vector>

using namespace facebook::react;

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

// ---- Ticket 10: RCTTextLayoutManager subclass (no swizzle) --------------------------------

static NSString *const kBuilderSelectorName = @"_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:";

// Private RN API, declared so `super` can be called. Only ever invoked by RN itself via `self`,
// so if RN renames it our override is simply never called (stock layout).
@interface RCTTextLayoutManager (TBPrivate)
- (NSTextStorage *)_textStorageAndLayoutManagerWithAttributesString:(NSAttributedString *)attributedString
                                                paragraphAttributes:(ParagraphAttributes)paragraphAttributes
                                                               size:(CGSize)size;
@end

@interface RCTBalancedTextLayoutManager : RCTTextLayoutManager
@end

static BOOL gHookAvailable = NO;
static std::vector<double> gSamples;

@implementation RCTBalancedTextLayoutManager

+ (void)initialize
{
  if (self != [RCTBalancedTextLayoutManager class]) {
    return;
  }
  NSString *name = kBuilderSelectorName;
  if ([[NSUserDefaults standardUserDefaults] boolForKey:@"TBSimulateMissingSelector"]) {
    name = @"_textStorageAndLayoutManagerWithAttributedString_RENAMED:paragraphAttributes:size:";
  }
  gHookAvailable = [RCTTextLayoutManager instancesRespondToSelector:NSSelectorFromString(name)];
  os_log(OS_LOG_DEFAULT, "[TextBalancer prototype] hook available=%d", gHookAvailable);
#if RCT_DEV
  if (!gHookAvailable) {
    RCTLogWarn(
        @"react-native-text-balancer: RCTTextLayoutManager no longer responds to %@; <Text balance> renders unbalanced on this React Native version.",
        name);
  }
#endif
}

- (NSTextStorage *)_textStorageAndLayoutManagerWithAttributesString:(NSAttributedString *)attributedString
                                                paragraphAttributes:(ParagraphAttributes)paragraphAttributes
                                                               size:(CGSize)size
{
  NSTextStorage *storage = [super _textStorageAndLayoutManagerWithAttributesString:attributedString
                                                                paragraphAttributes:paragraphAttributes
                                                                               size:size];
  if (!gHookAvailable || storage.length == 0 || !isfinite(size.width) || size.width <= 0 || size.width > 100000) {
    return storage;
  }

  CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
  NSLayoutManager *layoutManager = storage.layoutManagers.firstObject;
  NSTextContainer *container = layoutManager.textContainers.firstObject;
  CGFloat W = size.width;

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

  NSParagraphStyle *style = [storage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:nil];
  StripSide side = StripRight;
  if (style.alignment == NSTextAlignmentCenter) {
    side = StripBoth;
  } else if (!CGRectIsNull(shortest) && CGRectGetMinX(shortest) > W - CGRectGetMaxX(shortest) + 0.5) {
    side = StripLeft;
  }

  NSString *planInfo = @"-";
  NSTextContainer *active = container;
  if (!truncated && target > 1) {
    NSString *info = nil;
    NSTextContainer *plan = applyMinRaggedness(storage, layoutManager, container, side, &info);
    planInfo = info;
    if (plan != nil) {
      active = plan;
    }
  }
  active.size = savedSize;
  active.maximumNumberOfLines = savedMaxLines;
  active.lineBreakMode = savedMode;

  double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
  gSamples.push_back(ms);
  std::vector<double> sorted = gSamples;
  std::sort(sorted.begin(), sorted.end());
  os_log(
      OS_LOG_DEFAULT,
      "[TextBalancer prototype] balanced w=%.1f lines=%lu maxLines=%lu truncated=%d scaled=%d plan=%{public}@ %.3fms (median %.3fms n=%lu)",
      W,
      (unsigned long)target,
      (unsigned long)maxLines,
      truncated,
      paragraphAttributes.adjustsFontSizeToFit,
      planInfo,
      ms,
      sorted[sorted.size() / 2],
      (unsigned long)sorted.size());
  return storage;
}

@end

// ---- Ticket 10: C++ side -----------------------------------------------------------------

namespace facebook::react {

extern const char BalancedParagraphComponentName[] = "BalancedParagraph";

class BalancedParagraphShadowNode : public ParagraphShadowNode {
 public:
  using ParagraphShadowNode::ParagraphShadowNode;

  // Hide ConcreteShadowNode's statics so the descriptor registers "BalancedParagraph".
  static ComponentName Name()
  {
    return ComponentName(BalancedParagraphComponentName);
  }
  static ComponentHandle Handle()
  {
    return ComponentHandle(BalancedParagraphComponentName);
  }
};

class BalancedTextLayoutManager : public TextLayoutManager {
 public:
  explicit BalancedTextLayoutManager(const std::shared_ptr<const ContextContainer> &contextContainer)
      : TextLayoutManager(contextContainer)
  {
    nativeTextLayoutManager_ = wrapManagedObject([RCTBalancedTextLayoutManager new]);
  }
};

// Modelled on BaseParagraphComponentDescriptor, but with our own TextLayoutManager instance
// (own native manager, own measure caches), never the shared TextLayoutManagerKey one.
class BalancedParagraphComponentDescriptor final : public ConcreteComponentDescriptor<BalancedParagraphShadowNode> {
 public:
  explicit BalancedParagraphComponentDescriptor(const ComponentDescriptorParameters &parameters)
      : ConcreteComponentDescriptor<BalancedParagraphShadowNode>(parameters),
        textLayoutManager_(std::make_shared<BalancedTextLayoutManager>(contextContainer_))
  {
  }

 protected:
  void adopt(ShadowNode &shadowNode) const override
  {
    ConcreteComponentDescriptor<BalancedParagraphShadowNode>::adopt(shadowNode);
    static_cast<BalancedParagraphShadowNode &>(shadowNode).setTextLayoutManager(textLayoutManager_);
  }

 private:
  const std::shared_ptr<const TextLayoutManager> textLayoutManager_;
};

} // namespace facebook::react

// ---- Ticket 10: view -----------------------------------------------------------------------

@interface RCTBalancedParagraphComponentView : RCTParagraphComponentView
@end

@implementation RCTBalancedParagraphComponentView

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<BalancedParagraphComponentDescriptor>();
}

@end

// ---- Prototype-only: accessibility dump ----------------------------------------------------

static void dumpA11y(UIView *view, NSMutableString *out)
{
  if ([view isKindOfClass:[RCTParagraphComponentView class]]) {
    CGRect f = [view convertRect:view.bounds toView:nil];
    [out appendFormat:@"\n%@ frame=%@ isElement=%d label=%@ traits=%llu",
                      NSStringFromClass(view.class),
                      NSStringFromCGRect(f),
                      view.isAccessibilityElement,
                      view.accessibilityLabel,
                      (unsigned long long)view.accessibilityTraits];
    for (id el in view.accessibilityElements) {
      UIAccessibilityElement *e = el;
      [out appendFormat:@"\n    el label=%@ traits=%llu frame=%@ isElement=%d",
                        e.accessibilityLabel,
                        (unsigned long long)e.accessibilityTraits,
                        NSStringFromCGRect(e.accessibilityFrame),
                        e.isAccessibilityElement];
    }
    return;
  }
  for (UIView *sub in view.subviews) {
    dumpA11y(sub, out);
  }
}

__attribute__((constructor)) static void TBRegisterA11yDump(void)
{
  int token;
  notify_register_dispatch("tb.dumpa11y", &token, dispatch_get_main_queue(), ^(int) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
      for (UIWindow *window in ((UIWindowScene *)scene).windows) {
        NSMutableString *out = [NSMutableString new];
        dumpA11y(window, out);
        for (NSString *chunk in [out componentsSeparatedByString:@"\n"]) {
          if (chunk.length) {
            os_log(OS_LOG_DEFAULT, "[TextBalancer a11y] %{public}@", chunk);
          }
        }
      }
    }
  });
}
