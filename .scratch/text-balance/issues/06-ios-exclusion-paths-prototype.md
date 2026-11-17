Type: prototype
Status: resolved
Assignee: Sam Jusaitis (claimed)
Blocked by: 05

## Question

Does swapping the 04 spike's negative `tailIndent` for `NSTextContainer.exclusionPaths`, applied after RN's `scaleFontSizeToFitSize:`, remove both trade-offs from [04 iOS tailIndent injection prototype](04-ios-tailindent-injection-prototype.md) while keeping measure, draw, hit-test and `onTextLayout` in agreement? Specifically:

1. The pressed nested-span highlight (including a span that wraps across lines) stops at the balanced edge, not the box edge.
2. `adjustsFontSizeToFit` text balances after scaling and still fits; `numberOfLines` truncation is skipped or capped.
3. Centred, right-aligned and RTL text keep correct alignment (strip on the trailing side, or half on each side for centred).

Also record exclusion-path layout cost against the ~1ms `tailIndent` baseline, and note any interaction with the `enableIOSCompressedTextFrameAdjustment` path. Start from `ios/PrototypeBalanceSwizzle.mm`; approach and line refs in [research/ios-balancing-alternatives.md](../research/ios-balancing-alternatives.md).

## Answer

**Yes. `NSTextContainer.exclusionPaths`, applied after RN's `scaleFontSizeToFitSize:`, removes both 04 trade-offs**, and measure, draw, hit-test and `onTextLayout` still agree (RN 0.88.1, iOS 27.2 simulator, Debug build). Human-reviewed by Sam.

How the spike does it ([ios/PrototypeBalanceSwizzle.mm](../../../ios/PrototypeBalanceSwizzle.mm)):

- Same swizzle and `textBreakStrategy="balanced"` flag as 04. The hook calls the original first, so the storage is already font-scaled.
- It counts lines on RN's own stack, temporarily set to unlimited lines, word wrapping and a 1e7 height, then binary-searches (0.5pt) the widest exclusion strip that keeps the full-width line count. Then it restores RN's size, `maximumNumberOfLines` and `lineBreakMode`, and leaves the strip on the container. The container, and so the Yoga box, stays full width.
- Strip side: half on each side for `NSTextAlignmentCenter`; otherwise on the side opposite where the shortest full-width line sits. That covers left, right, RTL natural and `writingDirection: 'rtl'` without reading the paragraph style. Strip height is a finite 1e7, because measure passes `CGFLOAT_MAX`.
- `numberOfLines`: if the untruncated line count exceeds it, skip balancing; otherwise balance to that count.

Criteria:

1. **Highlight: pass.** A pinned and a real-pressed nested span that wraps across lines stops at the balanced edge for LTR, centred, right-aligned and RTL text. With balance off, the same span highlights to the box edge. Taps reach only the span; `onTextLayout` reports 195 / 223 / 200.
2. **`adjustsFontSizeToFit`: pass.** With `numberOfLines=2` it scales, then balances (inset 20pt), and measure and draw agree. `numberOfLines=2` that truncates: skipped. `numberOfLines=5` that fits: balanced. Edge: `adjustsFontSizeToFit` with no `numberOfLines` in a fixed-height box doesn't scale even in stock RN (the text is clipped); the spike balances the full text, so a different part is clipped.
3. **Alignment: pass.** Centred stays centred, right-aligned and `writingDirection: 'rtl'` keep their right edge with the strip on the left. Arabic with no `writingDirection` renders left-aligned in stock RN in an LTR app, and gets the strip on the right.

Cost: median 1.05ms per stack build (mean 1.34ms, p90 3.4ms including warm-up, 73 calls, Debug). That is in line with the ~1ms `tailIndent` baseline, so the non-simple-rectangular layout path costs nothing noticeable. It is still recomputed on every measure/draw/hit-test, so the (string, width, attrs) cache is still needed.

`enableIOSCompressedTextFrameAdjustment`: not exercised. From the code (`RTLM:72-128`), that path calls the same hook with `frame.size` and only adjusts height when a paragraph `maximumLineHeight` is set; balancing keeps the line count, so no conflict is expected.

Found along the way (stock RN, not the balancer): **RTL press highlight is drawn in the wrong place.** `drawAttributedString:` passes the `IsHighlighted` *character* range straight to `enumerateEnclosingRectsForGlyphRange:` (`RTLM:~297`). Arabic has a different glyph count than character count, so the box shifts earlier in the text (into the previous word, missing the span's last line). It happens with balance on and off. Hit-testing uses `characterIndexForPoint:` and is correct (verified: a tap inside the box but off the span is ignored, a tap on the span outside the box fires). Upstream fix: convert with `glyphRangeForCharacterRange:` first. The glyph/character mismatch is inferred from the code and screenshots, not counted.

Still open from 04: max-width squeeze rather than minimum raggedness; multi-paragraph text shares one strip; private-selector fragility.

Prototype code (throwaway branch `prototype/06-ios-exclusion-paths`; not on `master`): [ios/PrototypeBalanceSwizzle.mm](../../../ios/PrototypeBalanceSwizzle.mm) and the `HighlightProbe` / `FitProbe` samples plus an ON/OFF button in `example/App.tsx`. The pinned highlight forces the native `isHighlighted` prop through a prop spread.

Gotcha: `CI=1 npx expo start` disables Metro's file watching, so JS edits need a Metro restart to show up.
