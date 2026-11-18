# 02: Balance Latin text on iOS

Spec: [spec.md](../../text-balance/spec.md) (The iOS hook; Planning one paragraph; Imposing and checking the plan). Decisions: [ADR 0001](../../../docs/adr/0001-ios-polyfill-swizzle.md), tickets 06, 08 and 10 in [the map](../../text-balance/map.md).

**What to build:** after installing the library, a `Text` with `textBreakStrategy="balanced"` balances Latin text on iOS. Every other `Text` renders exactly as stock.

- The library replaces RN's private TextKit stack builder at load time. It does this only if the class, the selector and the method's type encoding all match. Otherwise it leaves RN untouched and logs one dev warning per process. Below RN 0.85 the build fails with a clear `#error`.
- For a balanced paragraph (k > 1 lines at full width):
  - plan a minimum-raggedness layout at the same line count, using space-separated words as break points and widths from one `CTLine`;
  - impose the plan with the per-line text container from ticket 08 (the Yoga box stays the stock size);
  - check that the laid-out line starts match the plan.
- On a mismatch, or when no plan fits, that paragraph keeps stock wrapping. Each paragraph balances or falls back independently.
- Line rects sit on the alignment side: trailing for left-aligned, leading for right-aligned and RTL, centred for centred text.

**Blocked by:** 01.

**Status:** in-review

- [x] The Latin headline samples (left, centred, right, RTL) and the multi-paragraph sample show ✅ "balanced" on iOS. Their "unchanged" twins show ✅.
- [x] Making the guard's checks fail on purpose (for example, a renamed selector) gives stock layout on every sample and exactly one dev warning.
- [ ] Nested pressable spans fire `onPress` and their highlight hugs the balanced lines. `selectable`, VoiceOver and `onTextLayout` behave as stock (checked by eye on the test screen).
- [x] Measure, draw, hit-test and `onTextLayout` agree: no clipped or overlapping text on any sample.

## Comments

- **Implementation:** `ios/RNTextBalancer.mm` (guard, `#error` floor, swizzle) and `ios/RNTBBalancer.{h,mm}` (plan, per-line container, check, per-paragraph fallback). Simulator, RN 0.88.1: 12/12, including a new "Nested pressable spans, selectable" sample. A renamed selector and a changed expected signature each gave stock layout on every sample plus exactly one dev warning.
- **Widths:** caret offsets (`CTLineGetOffsetForStringIndex`, as in prototype 08) return 0 for the end of an RTL-based line, so the RTL sample never planned. Widths use logical-order `CTRun` advances from the same `CTLine`, prefix-summed, as the spec says.
- **Still to check by eye:** tapping a nested span in the balanced copy fires `onPress`, and `selectable` works. The press highlight hugging the lines and VoiceOver weren't checked, so box 3 stays open.
- **Open question:** RN measures with `usedRectForTextContainer`, so a `Text` *without* a fixed width measures at its widest balanced line, narrower than stock. Draw then replans at that width. The line count stays k, because greedy wrapping at a width the k balanced lines fit in can't need more lines, so nothing clips. But that box isn't "the stock size". Every sample uses a fixed width.
- **Early from 04:** text that truncates at `numberOfLines` is left as stock, so truncation can't break.
