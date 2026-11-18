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

**Status:** ready-for-agent

- [ ] The Latin headline samples (left, centred, right, RTL) and the multi-paragraph sample show ✅ "balanced" on iOS. Their "unchanged" twins show ✅.
- [ ] Making the guard's checks fail on purpose (for example, a renamed selector) gives stock layout on every sample and exactly one dev warning.
- [ ] Nested pressable spans fire `onPress` and their highlight hugs the balanced lines. `selectable`, VoiceOver and `onTextLayout` behave as stock (checked by eye on the test screen).
- [ ] Measure, draw, hit-test and `onTextLayout` agree: no clipped or overlapping text on any sample.
