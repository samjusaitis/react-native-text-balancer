# 04: Scaling, clamping and fallbacks

Spec: [spec.md](../../text-balance/spec.md) (Planning one paragraph; Imposing and checking the plan). Detail: tickets 06, 12 (with its push-out amendment) and 14 in [the map](../../text-balance/map.md).

**What to build:** balanced text on iOS works correctly with `adjustsFontSizeToFit` and `numberOfLines`. It falls back cleanly to stock wrapping where it can't balance, and follows the `push-out` rule.

- `adjustsFontSizeToFit` scales first, then the scaled text balances.
- Text that fits within `numberOfLines` balances to that many lines. Text that truncates keeps stock wrapping and stock ellipsis.
- A paragraph containing a tab, or with a segment wider than the box, keeps stock wrapping.
- **Push-out:** while a checked plan is applied to a paragraph, `pushOut` is cleared from that paragraph's line-break strategy, so `standard` becomes hangul-word only. A paragraph that falls back gets its original style back. There's no warning.

**Blocked by:** 02.

**Status:** ready-for-agent

- [ ] Test-screen samples on iOS:
  - `adjustsFontSizeToFit` (with `numberOfLines`) shows ✅ "balanced";
  - `numberOfLines` that fits shows ✅ "balanced";
  - `numberOfLines` that truncates shows ✅ "stock";
  - a tab paragraph shows ✅ "stock";
  - a word wider than the box shows ✅ "stock";
  - `push-out` on a balancing paragraph shows ✅ "balanced";
  - `push-out` on a tab paragraph shows ✅ "stock", with `pushOut` still on its style.
- [ ] Every ticket 02 sample still passes.
