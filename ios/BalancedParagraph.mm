// PROTOTYPE (ticket 14): ticket 11's plan inputs (CFStringTokenizer candidates, logical CTRun advances,
// windowed DP, one repair retry) on top of the ticket 10 component. Throwaway.
//
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

static BOOL isHangul(unichar c)
{
  return (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F);
}

// PROTOTYPE (ticket 14): launch args.
//   -TBOldInputs YES  ticket 10 inputs (after-space candidates, |x(end) - x(start)| widths, full DP, no repair)
//   -TBDiag YES       per-build diagnostics (stock breaks missing from the candidates, predicted vs TextKit
//                     line widths, hyphenation defaults, repeat builds and their caller). Off for timing.
static BOOL gOldInputs = NO;
static BOOL gDiag = NO;
static BOOL gFakeCands = NO; // -TBFakeCands YES: add a bogus mid-token candidate per token (exercises repair)
// Phase times (ms) for the current build: full-width count layout, inputs, DP, imposed layout(s).
static double gTCount, gTInputs, gTDP, gTVerify;
static double tbNow() { return CFAbsoluteTimeGetCurrent() * 1000; }

// One paragraph of the stack (ticket 14).
struct TBPara {
  NSRange full; // paragraph range including its terminator
  NSRange r; // content range, terminator stripped
  NSUInteger k = 0; // full-width line count
  NSString *skip = nil; // reason the paragraph is not planned
  std::vector<NSUInteger> cands; // candidate line starts, relative, including 0 and len
  // Inputs per candidate index: width(a, b) = endX[b] - startX[a] (new) or |endX[b] - startX[a]| (old).
  std::vector<CGFloat> startX, endX;
  bool planned = false;
  bool pushOut = false; // ticket 15 rule: pushOut is cleared only while this paragraph's plan is applied
  std::vector<std::pair<NSRange, NSParagraphStyle *>> origStyles; // to restore pushOut on fallback
  std::vector<NSUInteger> starts; // absolute planned line starts
  std::vector<CGFloat> predicted; // predicted width per planned line
  std::vector<std::pair<NSUInteger, CGFloat>> widths; // absolute line start -> fragment width
};

// Ticket 10/08 inputs: starts of words after a space, visual caret offsets from one CTLine.
static void buildOldInputs(NSAttributedString *storage, TBPara &p)
{
  NSString *text = [storage.string substringWithRange:p.r];
  NSUInteger len = text.length;
  p.cands = {0};
  for (NSUInteger i = 1; i < len; i++) {
    if (isBreakSpace([text characterAtIndex:i - 1]) && !isBreakSpace([text characterAtIndex:i])) {
      p.cands.push_back(i);
    }
  }
  p.cands.push_back(len);
  size_t m = p.cands.size();
  CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)[storage attributedSubstringFromRange:p.r]);
  p.startX.assign(m, 0);
  p.endX.assign(m, 0);
  for (size_t j = 0; j < m; j++) {
    NSUInteger e = p.cands[j];
    while (e > 0 && isBreakSpace([text characterAtIndex:e - 1])) {
      e--;
    }
    p.startX[j] = CTLineGetOffsetForStringIndex(line, p.cands[j], NULL);
    p.endX[j] = CTLineGetOffsetForStringIndex(line, e, NULL);
  }
  CFRelease(line);
}

// Ticket 11 inputs: CFStringTokenizer line-break units, logical-order CTRun advances.
static void buildNewInputs(NSAttributedString *storage, TBPara &p, NSParagraphStyle *style)
{
  NSString *text = [storage.string substringWithRange:p.r];
  NSUInteger len = text.length;
  std::vector<unichar> chars(len);
  [text getCharacters:chars.data() range:NSMakeRange(0, len)];

  // Candidates.
  std::vector<NSUInteger> c{0};
  CFStringTokenizerRef tok =
      CFStringTokenizerCreate(NULL, (CFStringRef)text, CFRangeMake(0, len), kCFStringTokenizerUnitLineBreak, NULL);
  while (CFStringTokenizerAdvanceToNextToken(tok) != kCFStringTokenizerTokenNone) {
    CFRange tr = CFStringTokenizerGetCurrentTokenRange(tok);
    if (tr.location > 0 && (NSUInteger)tr.location < len) {
      c.push_back(tr.location);
    }
  }
  CFRelease(tok);
  for (NSUInteger i = 0; i < len; i++) {
    if (chars[i] == 0xFFFC) {
      if (i > 0) c.push_back(i);
      if (i + 1 < len) c.push_back(i + 1);
    }
  }
  if (gFakeCands) {
    std::sort(c.begin(), c.end());
    c.erase(std::unique(c.begin(), c.end()), c.end());
    size_t n = c.size();
    for (size_t t = 0; t < n; t++) {
      NSUInteger a = c[t], b = t + 1 < n ? c[t + 1] : len;
      if (b - a >= 6) c.push_back(a + (b - a) / 2);
    }
  }
  c.push_back(len);
  std::sort(c.begin(), c.end());
  c.erase(std::unique(c.begin(), c.end()), c.end());
  if (style.lineBreakStrategy & NSLineBreakStrategyHangulWordPriority) {
    c.erase(std::remove_if(c.begin() + 1, c.end() - 1, [&](NSUInteger i) { return isHangul(chars[i - 1]) && isHangul(chars[i]); }),
            c.end() - 1);
  }
  p.cands = c;

  // Logical-order advances per UTF-16 unit, from one CTLine.
  std::vector<CGFloat> adv(len, 0);
  NSAttributedString *sub = [storage attributedSubstringFromRange:p.r];
  CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)sub);
  CFArrayRef runs = CTLineGetGlyphRuns(line);
  std::vector<CGSize> a;
  std::vector<CFIndex> idx;
  for (CFIndex r = 0; r < CFArrayGetCount(runs); r++) {
    CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
    CFIndex n = CTRunGetGlyphCount(run);
    a.resize(n);
    idx.resize(n);
    CTRunGetAdvances(run, CFRangeMake(0, 0), a.data());
    CTRunGetStringIndices(run, CFRangeMake(0, 0), idx.data());
    for (CFIndex g = 0; g < n; g++) {
      if (idx[g] >= 0 && (NSUInteger)idx[g] < len) {
        adv[idx[g]] += a[g].width;
      }
    }
  }
  CFRelease(line);
  for (NSUInteger i = 0; i < len; i++) {
    if (chars[i] == 0xFFFC) {
      NSTextAttachment *att = [sub attribute:NSAttachmentAttributeName atIndex:i effectiveRange:NULL];
      if (att) {
        adv[i] = att.bounds.size.width;
      }
    }
  }
  std::vector<CGFloat> P(len + 1, 0);
  for (NSUInteger i = 0; i < len; i++) {
    P[i + 1] = P[i] + adv[i];
  }

  size_t m = c.size();
  p.startX.assign(m, 0);
  p.endX.assign(m, 0);
  for (size_t j = 0; j < m; j++) {
    NSUInteger b = c[j];
    NSUInteger e = b;
    while (e > 0 && isBreakSpace(chars[e - 1])) {
      e--;
    }
    CGFloat extra = 0;
    if (b > 0 && b < len && chars[b - 1] == 0x00AD) {
      UIFont *font = [sub attribute:NSFontAttributeName atIndex:b - 1 effectiveRange:NULL];
      if (font) {
        UniChar h = '-';
        CGGlyph g;
        if (CTFontGetGlyphsForCharacters((__bridge CTFontRef)font, &h, &g, 1)) {
          extra = CTFontGetAdvancesForGlyphs((__bridge CTFontRef)font, kCTFontOrientationHorizontal, &g, NULL, 1);
        }
      }
    }
    p.startX[j] = P[b];
    p.endX[j] = P[e] + extra;
  }
}

// Min-raggedness DP over the paragraph's candidates. Fills p.starts / p.widths / p.predicted.
static bool planParagraph(TBPara &p, CGFloat U, CGFloat padding)
{
  p.planned = false;
  p.starts.clear();
  p.widths.clear();
  p.predicted.clear();
  size_t m = p.cands.size() - 1; // segments
  size_t k = p.k;
  if (m < k) {
    return false;
  }
  const bool old = gOldInputs;
  auto width = [&](size_t a, size_t b) -> CGFloat {
    CGFloat w = p.endX[b] - p.startX[a];
    return old ? (CGFloat)fabs(w) : MAX((CGFloat)0, w);
  };

  const double INF = 1e300;
  std::vector<std::vector<double>> dp(k + 1, std::vector<double>(m + 1, INF));
  std::vector<std::vector<size_t>> from(k + 1, std::vector<size_t>(m + 1, 0));
  dp[0][0] = 0;
  for (size_t l = 1; l <= k; l++) {
    for (size_t j = l; j <= m; j++) {
      for (size_t i = j; i-- > l - 1;) {
        CGFloat w = width(i, j);
        if (w > U + 0.5) {
          if (old) continue; // ticket 10: full O(m^2) scan
          break; // ticket 11: widths grow as i moves left, so the window ends here
        }
        if (dp[l - 1][i] >= INF) {
          continue;
        }
        double cost = dp[l - 1][i] + (U - w) * (U - w);
        if (cost < dp[l][j]) {
          dp[l][j] = cost;
          from[l][j] = i;
        }
      }
    }
  }
  if (dp[k][m] >= INF) {
    return false;
  }
  std::vector<size_t> bounds(k + 1);
  bounds[k] = m;
  for (size_t l = k; l > 0; l--) {
    bounds[l - 1] = from[l][bounds[l]];
  }
  for (size_t l = 0; l < k; l++) {
    size_t a = bounds[l], b = bounds[l + 1];
    NSUInteger start = p.r.location + p.cands[a];
    CGFloat w = width(a, b);
    p.starts.push_back(start);
    p.predicted.push_back(w);
    if (b == m) {
      continue; // last line: full width
    }
    CGFloat withNext = width(a, b + 1);
    CGFloat slack = MAX(1.0, MIN(4.0, (withNext - w) / 2));
    p.widths.push_back({start, MIN(U, w + slack) + 2 * padding});
  }
  p.planned = true;
  return true;
}

static NSArray<NSNumber *> *lineStarts(NSLayoutManager *layoutManager, NSTextContainer *container, std::vector<CGFloat> *usedWidths = nullptr)
{
  [layoutManager ensureLayoutForTextContainer:container];
  NSMutableArray<NSNumber *> *starts = [NSMutableArray new];
  NSRange glyphRange = [layoutManager glyphRangeForTextContainer:container];
  [layoutManager enumerateLineFragmentsForGlyphRange:glyphRange
                                          usingBlock:^(CGRect, CGRect used, NSTextContainer *, NSRange g, BOOL *) {
                                            [starts addObject:@([layoutManager characterRangeForGlyphRange:g
                                                                                          actualGlyphRange:NULL]
                                                                    .location)];
                                            if (usedWidths) {
                                              // Width without trailing whitespace (TextKit squeezes a trailing
                                              // space into the fragment, so usedRect includes the slack).
                                              NSRange cr = [layoutManager characterRangeForGlyphRange:g actualGlyphRange:NULL];
                                              NSString *str = layoutManager.textStorage.string;
                                              while (cr.length > 0 &&
                                                     [[NSCharacterSet whitespaceAndNewlineCharacterSet]
                                                         characterIsMember:[str characterAtIndex:NSMaxRange(cr) - 1]]) {
                                                cr.length--;
                                              }
                                              NSRange tg = [layoutManager glyphRangeForCharacterRange:cr actualCharacterRange:NULL];
                                              usedWidths->push_back(
                                                  tg.length ? [layoutManager boundingRectForGlyphRange:tg inTextContainer:container].size.width : 0);
                                            }
                                          }];
  return starts;
}

// Per-build stats for the log (ticket 14).
struct TBPlanStats {
  NSUInteger planned = 0; // paragraphs planned
  NSUInteger skipped = 0; // paragraphs skipped (tab / pushOut)
  NSUInteger infeasible = 0;
  NSUInteger cands = 0;
  NSUInteger stockNotCand = 0; // diag: stock full-width breaks missing from the candidates
  int repair = 0; // 0 none needed, 1 repaired, -1 failed (stock), -2 mismatch without repair (old inputs)
  CGFloat maxDW = 0; // diag: max |predicted - TextKit used width| over planned lines
  CGFloat attDW = NAN; // diag: same, only lines containing an attachment
};

// Clears NSLineBreakStrategyPushOut on a range (every paragraph style run in it).
static void clearPushOut(NSTextStorage *storage, NSRange r)
{
  [storage enumerateAttribute:NSParagraphStyleAttributeName
                      inRange:r
                      options:0
                   usingBlock:^(NSParagraphStyle *ps, NSRange sub, BOOL *) {
                     if (ps && (ps.lineBreakStrategy & NSLineBreakStrategyPushOut)) {
                       NSMutableParagraphStyle *m = [ps mutableCopy];
                       m.lineBreakStrategy &= ~NSLineBreakStrategyPushOut;
                       [storage addAttribute:NSParagraphStyleAttributeName value:m range:sub];
                     }
                   }];
}

// Swaps in a TBPlanContainer imposing a min-raggedness plan. Expects `container` in counting
// configuration (W x 1e7, unlimited lines). Returns the new container, or nil on failure (RN's
// container is then back in place). `outInfo` gets a short description for the log.
static NSTextContainer *applyMinRaggedness(
    NSTextStorage *storage,
    NSLayoutManager *layoutManager,
    NSTextContainer *container,
    StripSide side,
    NSString **outInfo,
    TBPlanStats &stats,
    NSMutableArray<NSValue *> *clearedPushOut)
{
  NSArray<NSNumber *> *fullStarts = lineStarts(layoutManager, container);
  NSString *string = storage.string;
  CGFloat padding = container.lineFragmentPadding;
  CGFloat U = container.size.width - 2 * padding;

  // Group full-width lines by paragraph.
  std::vector<TBPara> paras;
  for (NSNumber *s in fullStarts) {
    NSRange pr = [string paragraphRangeForRange:NSMakeRange(s.unsignedIntegerValue, 0)];
    if (!paras.empty() && NSEqualRanges(paras.back().full, pr)) {
      paras.back().k++;
    } else {
      TBPara p;
      p.full = pr;
      p.k = 1;
      paras.push_back(p);
    }
  }

  NSMutableString *info = [NSMutableString new];
  for (size_t i = 0; i < paras.size(); i++) {
    TBPara &p = paras[i];
    NSRange r = p.full;
    while (r.length > 0 && [[NSCharacterSet newlineCharacterSet] characterIsMember:[string characterAtIndex:NSMaxRange(r) - 1]]) {
      r.length--;
    }
    p.r = r;
    [info appendFormat:@"%@%lu", i ? @"," : @"", (unsigned long)p.k];
    if (p.k <= 1 || r.length == 0) {
      continue;
    }
    NSParagraphStyle *style = [storage attribute:NSParagraphStyleAttributeName atIndex:r.location effectiveRange:NULL];
    if (!gOldInputs) {
      if ([[string substringWithRange:r] rangeOfString:@"\t"].location != NSNotFound) {
        p.skip = @"tab";
      }
    }
    // Ticket 15 rule (replaces ticket 11's "skip pushOut"): plan it anyway; pushOut is cleared only
    // while the plan is applied and restored if the paragraph falls back to stock wrapping.
    if (!p.skip) {
      [storage enumerateAttribute:NSParagraphStyleAttributeName
                          inRange:r
                          options:0
                       usingBlock:^(NSParagraphStyle *ps, NSRange sub, BOOL *) {
                         if (ps && (ps.lineBreakStrategy & NSLineBreakStrategyPushOut)) {
                           p.pushOut = true;
                         }
                         p.origStyles.push_back({sub, ps});
                       }];
      if (p.pushOut) [info appendString:@"[pushOut]"];
    }
    if (p.skip) {
      stats.skipped++;
      [info appendFormat:@"[skip %@]", p.skip];
      continue;
    }
    double t0 = tbNow();
    if (gOldInputs) {
      buildOldInputs(storage, p);
    } else {
      buildNewInputs(storage, p, style);
    }
    gTInputs += tbNow() - t0;
    stats.cands += p.cands.size();
    if (gDiag) {
      for (NSNumber *s in fullStarts) {
        NSUInteger v = s.unsignedIntegerValue;
        if (v > r.location && v < NSMaxRange(r) &&
            !std::binary_search(p.cands.begin(), p.cands.end(), v - r.location)) {
          stats.stockNotCand++;
        }
      }
    }
    double t1 = tbNow();
    bool ok = planParagraph(p, U, padding);
    gTDP += tbNow() - t1;
    if (ok) {
      stats.planned++;
    } else {
      stats.infeasible++;
      [info appendString:@"!"]; // plan infeasible
    }
  }

  NSMutableDictionary<NSNumber *, NSNumber *> *widths = [NSMutableDictionary new];
  NSMutableArray<NSNumber *> *planStarts = [NSMutableArray new];
  auto assemble = [&]() {
    [widths removeAllObjects];
    [planStarts removeAllObjects];
    for (TBPara &p : paras) {
      if (p.planned) {
        for (NSUInteger s : p.starts) [planStarts addObject:@(s)];
        for (auto &w : p.widths) widths[@(w.first)] = @(w.second);
      } else {
        // Unplanned paragraph: keep its full-width breaks.
        for (NSNumber *s in fullStarts) {
          NSUInteger v = s.unsignedIntegerValue;
          if (v >= p.full.location && v < NSMaxRange(p.full)) {
            [planStarts addObject:s];
          }
        }
      }
    }
  };
  assemble();
  // Apply the pushOut rule for the current plan state: cleared on planned paragraphs, original elsewhere.
  auto syncPushOut = [&](bool fallback) {
    [storage beginEditing];
    for (TBPara &p : paras) {
      if (!p.pushOut) continue;
      if (p.planned && !fallback) {
        clearPushOut(storage, p.r);
      } else {
        for (auto &o : p.origStyles) {
          if (o.second) [storage addAttribute:NSParagraphStyleAttributeName value:o.second range:o.first];
        }
      }
    }
    [storage endEditing];
  };
  syncPushOut(false);

  TBPlanContainer *plan = [[TBPlanContainer alloc] initWithSize:container.size];
  plan.lineFragmentPadding = padding;
  plan.maximumNumberOfLines = 0;
  plan.lineBreakMode = NSLineBreakByWordWrapping;
  plan.lineWidths = widths;
  plan.side = side;
  [layoutManager removeTextContainerAtIndex:0];
  [layoutManager addTextContainer:plan];

  std::vector<CGFloat> used;
  double tv = tbNow();
  NSArray<NSNumber *> *got = lineStarts(layoutManager, plan);
  gTVerify += tbNow() - tv;
  NSMutableString *out = [NSMutableString stringWithFormat:@"paras=[%@] planned=%lu", info, (unsigned long)widths.count];
  if (![got isEqualToArray:planStarts]) {
    [out appendFormat:@" MISMATCH got=%@ want=%@", [got componentsJoinedByString:@" "], [planStarts componentsJoinedByString:@" "]];
    bool repaired = false;
    if (!gOldInputs) {
      // Repair: at the first disagreement, drop the planned candidate, add TextKit's break, re-plan
      // that paragraph, lay out once more.
      NSUInteger d = 0;
      while (d < got.count && d < planStarts.count && [got[d] isEqual:planStarts[d]]) d++;
      NSUInteger want = d < planStarts.count ? planStarts[d].unsignedIntegerValue : NSNotFound;
      NSUInteger tk = d < got.count ? got[d].unsignedIntegerValue : NSNotFound;
      NSUInteger anchor = want != NSNotFound ? want : tk;
      for (TBPara &p : paras) {
        if (!p.planned || anchor < p.full.location || anchor >= NSMaxRange(p.full)) continue;
        std::vector<NSUInteger> &c = p.cands;
        if (want != NSNotFound && want > p.r.location && want < NSMaxRange(p.r)) {
          c.erase(std::remove(c.begin(), c.end(), want - p.r.location), c.end());
        }
        if (tk != NSNotFound && tk > p.r.location && tk < NSMaxRange(p.r)) {
          c.push_back(tk - p.r.location);
          std::sort(c.begin(), c.end());
          c.erase(std::unique(c.begin(), c.end()), c.end());
        }
        // Rebuild widths for the edited candidate list.
        NSParagraphStyle *style = [storage attribute:NSParagraphStyleAttributeName atIndex:p.r.location effectiveRange:NULL];
        std::vector<NSUInteger> keep = c;
        buildNewInputs(storage, p, style);
        // buildNewInputs regenerates candidates; restore the edited list and recompute X for it.
        std::vector<NSUInteger> fresh = p.cands;
        std::vector<CGFloat> fs = p.startX, fe = p.endX;
        p.cands = keep;
        p.startX.assign(keep.size(), 0);
        p.endX.assign(keep.size(), 0);
        for (size_t j = 0; j < keep.size(); j++) {
          auto it = std::lower_bound(fresh.begin(), fresh.end(), keep[j]);
          if (it != fresh.end() && *it == keep[j]) {
            size_t f = it - fresh.begin();
            p.startX[j] = fs[f];
            p.endX[j] = fe[f];
          } else {
            // TextKit's break is not a tokenizer candidate: measure it with a one-off prefix.
            NSAttributedString *sub = [storage attributedSubstringFromRange:NSMakeRange(p.r.location, keep[j])];
            CTLineRef l = CTLineCreateWithAttributedString((CFAttributedStringRef)sub);
            CGFloat x = CTLineGetTypographicBounds(l, NULL, NULL, NULL);
            CGFloat trail = CTLineGetTrailingWhitespaceWidth(l);
            CFRelease(l);
            p.startX[j] = x;
            p.endX[j] = x - trail;
          }
        }
        if (!planParagraph(p, U, padding)) {
          p.planned = false;
        }
        break;
      }
      assemble();
      syncPushOut(false);
      plan.lineWidths = widths;
      [layoutManager textContainerChangedGeometry:plan];
      used.clear();
      tv = tbNow();
      NSArray<NSNumber *> *got2 = lineStarts(layoutManager, plan);
      gTVerify += tbNow() - tv;
      repaired = [got2 isEqualToArray:planStarts];
      [out appendFormat:@" REPAIR %@", repaired ? @"ok" : [NSString stringWithFormat:@"FAIL got=%@ want=%@",
                                                                                  [got2 componentsJoinedByString:@" "],
                                                                                  [planStarts componentsJoinedByString:@" "]]];
    }
    stats.repair = repaired ? 1 : (gOldInputs ? -2 : -1);
    if (!repaired) {
      syncPushOut(true);
      for (TBPara &p : paras) {
        if (p.pushOut) [out appendString:@" pushOut-restored"];
      }
      *outInfo = out;
      [layoutManager removeTextContainerAtIndex:0];
      [layoutManager addTextContainer:container];
      return nil;
    }
  }
  if (gDiag) {
    // Predicted vs TextKit's used width for every planned line.
    lineStarts(layoutManager, plan, &used);
    NSUInteger li = 0;
    for (TBPara &p : paras) {
      if (!p.planned) {
        for (NSNumber *s in fullStarts) {
          NSUInteger v = s.unsignedIntegerValue;
          if (v >= p.full.location && v < NSMaxRange(p.full)) li++;
        }
        continue;
      }
      for (size_t l = 0; l < p.starts.size(); l++, li++) {
        if (li >= used.size()) break;
        CGFloat dw = used[li] - p.predicted[l];
        if (fabs(dw) > fabs(stats.maxDW)) stats.maxDW = dw;
        NSUInteger end = l + 1 < p.starts.size() ? p.starts[l + 1] : NSMaxRange(p.r);
        if ([[string substringWithRange:NSMakeRange(p.starts[l], end - p.starts[l])] rangeOfString:@"￼"].location != NSNotFound) {
          if (isnan(stats.attDW) || fabs(dw) > fabs(stats.attDW)) stats.attDW = dw;
        }
      }
    }
  }
  for (TBPara &p : paras) {
    if (p.pushOut && p.planned) {
      [clearedPushOut addObject:[NSValue valueWithRange:p.r]];
      [out appendString:@" pushOut-cleared"];
    } else if (p.pushOut) {
      [out appendString:@" pushOut-kept"];
    }
  }
  *outInfo = out;
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

// ---- Ticket 14: plan cache (prototype, -TBCache YES) ---------------------------------------
// Content-addressed: the key is everything the plan depends on, so there is nothing to invalidate.
// Lives inside the builder because draw, hit-test and getRect rebuild the stack uncached.
@interface TBPlanKey : NSObject <NSCopying>
@property (nonatomic, copy) NSAttributedString *string; // RN's input string (before font scaling)
@property (nonatomic) CGFloat width;
@property (nonatomic) CGFloat height; // only when adjustsFontSizeToFit (scaling depends on it)
@property (nonatomic) NSUInteger maxLines;
@property (nonatomic) BOOL fit;
@end
@implementation TBPlanKey
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSUInteger)hash { return self.string.string.hash ^ (NSUInteger)(self.width * 64) ^ (self.maxLines << 20); }
- (BOOL)isEqual:(TBPlanKey *)o
{
  return [o isKindOfClass:TBPlanKey.class] && o.width == self.width && o.height == self.height &&
      o.maxLines == self.maxLines && o.fit == self.fit && [o.string isEqualToAttributedString:self.string];
}
@end
@interface TBPlanEntry : NSObject
@property (nonatomic, copy) NSDictionary<NSNumber *, NSNumber *> *lineWidths; // nil = stock layout
@property (nonatomic) NSInteger side;
@property (nonatomic, copy) NSArray<NSValue *> *clearedPushOut; // paragraph ranges whose pushOut the plan clears
@end
@implementation TBPlanEntry
@end
static BOOL gCache = NO;
static NSCache<TBPlanKey *, TBPlanEntry *> *gPlanCache;
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
  gOldInputs = [[NSUserDefaults standardUserDefaults] boolForKey:@"TBOldInputs"];
  gDiag = [[NSUserDefaults standardUserDefaults] boolForKey:@"TBDiag"];
  gFakeCands = [[NSUserDefaults standardUserDefaults] boolForKey:@"TBFakeCands"];
  gCache = [[NSUserDefaults standardUserDefaults] boolForKey:@"TBCache"];
  gPlanCache = [NSCache new];
  gPlanCache.countLimit = 256;
  os_log(OS_LOG_DEFAULT, "[TextBalancer prototype] hook available=%d oldInputs=%d diag=%d", gHookAvailable, gOldInputs, gDiag);
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

  TBPlanKey *cacheKey = nil;
  if (gCache) {
    cacheKey = [TBPlanKey new];
    cacheKey.string = attributedString;
    cacheKey.width = size.width;
    cacheKey.fit = paragraphAttributes.adjustsFontSizeToFit;
    cacheKey.height = cacheKey.fit ? size.height : 0;
    cacheKey.maxLines = paragraphAttributes.maximumNumberOfLines;
    TBPlanEntry *hit = [gPlanCache objectForKey:cacheKey];
    if (hit) {
      if (hit.lineWidths) {
        TBPlanContainer *plan = [[TBPlanContainer alloc] initWithSize:container.size];
        plan.lineFragmentPadding = container.lineFragmentPadding;
        plan.maximumNumberOfLines = container.maximumNumberOfLines;
        plan.lineBreakMode = container.lineBreakMode;
        plan.lineWidths = hit.lineWidths;
        plan.side = hit.side;
        if (hit.clearedPushOut.count) {
          [storage beginEditing];
          for (NSValue *v in hit.clearedPushOut) clearPushOut(storage, v.rangeValue);
          [storage endEditing];
        }
        [layoutManager removeTextContainerAtIndex:0];
        [layoutManager addTextContainer:plan];
      }
      double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
      static std::vector<double> hits;
      hits.push_back(ms);
      std::vector<double> sorted = hits;
      std::sort(sorted.begin(), sorted.end());
      os_log(OS_LOG_DEFAULT, "[TextBalancer prototype] HIT \"%{public}@\" w=%.1f %{public}s %.3fms | hit median %.3fms p90 %.3fms n=%lu",
             [attributedString.string substringToIndex:MIN((NSUInteger)18, attributedString.length)], size.width,
             hit.lineWidths ? "plan" : "stock", ms, sorted[sorted.size() / 2],
             sorted[std::min(sorted.size() - 1, (size_t)(sorted.size() * 0.9))], (unsigned long)sorted.size());
      return storage;
    }
  }
  CGFloat W = size.width;

  CGSize savedSize = container.size;
  NSUInteger savedMaxLines = container.maximumNumberOfLines;
  NSLineBreakMode savedMode = container.lineBreakMode;
  container.size = CGSizeMake(W, kStripHeight);
  container.maximumNumberOfLines = 0;
  container.lineBreakMode = NSLineBreakByWordWrapping;

  gTCount = gTInputs = gTDP = gTVerify = 0;
  CGRect shortest;
  double tc = tbNow();
  NSUInteger target = countLines(layoutManager, container, &shortest);
  gTCount = tbNow() - tc;
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
  TBPlanStats stats;
  bool attempted = !truncated && target > 1;
  NSMutableArray<NSValue *> *cleared = [NSMutableArray new];
  if (attempted) {
    NSString *info = nil;
    NSTextContainer *plan = applyMinRaggedness(storage, layoutManager, container, side, &info, stats, cleared);
    planInfo = info;
    if (plan != nil) {
      active = plan;
    }
  }
  active.size = savedSize;
  active.maximumNumberOfLines = savedMaxLines;
  active.lineBreakMode = savedMode;
  if (cacheKey) {
    TBPlanEntry *entry = [TBPlanEntry new];
    if (active != container) {
      entry.lineWidths = ((TBPlanContainer *)active).lineWidths;
      entry.side = ((TBPlanContainer *)active).side;
      entry.clearedPushOut = cleared;
    }
    [gPlanCache setObject:entry forKey:cacheKey];
  }

  double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;

  // ---- everything below is outside the timed region ----
  gSamples.push_back(ms);
  static std::vector<double> sC, sI, sD, sV;
  sC.push_back(gTCount); sI.push_back(gTInputs); sD.push_back(gTDP); sV.push_back(gTVerify);
  auto med = [](std::vector<double> v) { std::sort(v.begin(), v.end()); return v[v.size() / 2]; };
  NSString *phases = [NSString stringWithFormat:@" | phase medians count %.3f inputs %.3f dp %.3f layout %.3f",
                                                med(sC), med(sI), med(sD), med(sV)];
  static NSUInteger nAttempted = 0, nFirstTry = 0, nRepaired = 0, nFailed = 0;
  if (attempted && stats.planned > 0) {
    nAttempted++;
    if (stats.repair == 0) nFirstTry++;
    if (stats.repair == 1) nRepaired++;
    if (stats.repair < 0) nFailed++;
  }
  std::vector<double> sorted = gSamples;
  std::sort(sorted.begin(), sorted.end());
  double p90 = sorted[std::min(sorted.size() - 1, (size_t)(sorted.size() * 0.9))];
  NSString *head = [[attributedString.string substringToIndex:MIN((NSUInteger)18, attributedString.length)]
      stringByReplacingOccurrencesOfString:@"\n"
                                withString:@"⏎"];

  NSString *diag = @"";
  if (gDiag) {
    // Repeat builds for the same string+attributes, width and paragraph attributes, and who asked.
    static NSMutableDictionary<NSArray *, NSNumber *> *seen = [NSMutableDictionary new];
    NSArray *key = @[
      [attributedString copy],
      @(size.width),
      @(size.height),
      @(paragraphAttributes.maximumNumberOfLines),
      @(paragraphAttributes.adjustsFontSizeToFit),
      @((int)paragraphAttributes.ellipsizeMode),
    ];
    NSUInteger n = seen[key].unsignedIntegerValue + 1;
    seen[key] = @(n);
    NSString *caller = @"?";
    for (NSString *frame in [NSThread callStackSymbols]) {
      NSRange r = [frame rangeOfString:@"-[RCTTextLayoutManager "];
      if (r.location == NSNotFound) {
        r = [frame rangeOfString:@"facebook::react::"];
        if (r.location == NSNotFound || [frame containsString:@"RCTBalanced"]) continue;
      }
      caller = [[frame substringFromIndex:r.location] componentsSeparatedByString:@" + "].firstObject;
      if ([caller containsString:@"_textStorageAndLayoutManager"]) continue;
      break;
    }
    NSParagraphStyle *ps = style;
    diag = [NSString stringWithFormat:@" | diag seen=%lu caller=%@ stockNotCand=%lu dW=%.2f attDW=%.2f hyph(ps.default=%d ps.factor=%.2f lm.default=%d lm.factor=%.2f) lbs=%lu",
                                      (unsigned long)n, caller, (unsigned long)stats.stockNotCand, stats.maxDW, stats.attDW,
                                      ps.usesDefaultHyphenation, ps.hyphenationFactor, layoutManager.usesDefaultHyphenation,
                                      layoutManager.hyphenationFactor, (unsigned long)ps.lineBreakStrategy];
  }
  os_log(
      OS_LOG_DEFAULT,
      "[TextBalancer prototype] %{public}s \"%{public}@\" w=%.1f lines=%lu trunc=%d plan=%{public}@ cands=%lu %.3fms | median %.3fms p90 %.3fms n=%lu | builds first-try %lu repaired %lu stock %lu of %lu%{public}@",
      gOldInputs ? "OLD" : "NEW",
      head,
      W,
      (unsigned long)target,
      truncated,
      planInfo,
      (unsigned long)stats.cands,
      ms,
      sorted[sorted.size() / 2],
      p90,
      (unsigned long)sorted.size(),
      (unsigned long)nFirstTry,
      (unsigned long)nRepaired,
      (unsigned long)nFailed,
      (unsigned long)nAttempted,
      [phases stringByAppendingString:diag]);
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
