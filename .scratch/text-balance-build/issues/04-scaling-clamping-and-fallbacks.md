# 04: Scaling, clamping and fallbacks

Spec: [spec.md](../../text-balance/spec.md) (Choosing balanced breaks for one paragraph; Imposing and checking the balanced breaks). Detail: tickets 06, 12 (with its push-out amendment) and 14 in [the map](../../text-balance/map.md).

**What to build:** balanced text on iOS works correctly with `adjustsFontSizeToFit` and `numberOfLines`. It falls back cleanly to stock wrapping where it can't balance, and follows the `push-out` rule.

- `adjustsFontSizeToFit` scales first, then the scaled text balances.
- Text that fits within `numberOfLines` balances to that many lines. Text that truncates keeps stock wrapping and stock ellipsis.
- A paragraph containing a tab, or with a segment wider than the box, keeps stock wrapping.
- **Push-out:** while checked balanced breaks are applied to a paragraph, `pushOut` is cleared from that paragraph's line-break strategy, so `standard` becomes hangul-word only. A paragraph that falls back gets its original style back. There's no warning.

**Blocked by:** 02.

**Status:** done

- [x] Test-screen samples on iOS:
  - `adjustsFontSizeToFit` (with `numberOfLines`) shows ✅ "balanced";
  - `numberOfLines` that fits shows ✅ "balanced";
  - `numberOfLines` that truncates shows ✅ "stock";
  - a tab paragraph shows ✅ "stock";
  - a word wider than the box shows ✅ "stock";
  - `push-out` on a balancing paragraph shows ✅ "balanced";
  - `push-out` on a tab paragraph shows ✅ "stock", with `pushOut` still on its style.
- [x] Every ticket 02 sample still passes.

## Comments

- **Implementation:** `ios/RNTBBalancer.mm`. A paragraph containing a tab gets no balanced breaks, so it keeps stock wrapping. Push-out: each balanced paragraph records its paragraph-style runs that have `pushOut`. Before the balanced breaks are imposed, and after each repair or fallback in the check loop, those runs are brought in line with the paragraph's state: `pushOut` cleared (`strategy & hangulWordPriority`, so `standard` becomes hangul-word only) on balanced paragraphs, original style back on the rest, and every original style back if the whole storage returns to stock. The truncation check and the "no balanced breaks fit" fallback were already there from tickets 02 and 03. `adjustsFontSizeToFit` needs no code: RN's builder scales the storage before the hook runs.
- **Test screen:** simulator, RN 0.88.1, Debug: 46/46. New samples: `adjustsFontSizeToFit` with `numberOfLines` 3, `numberOfLines` that fits and that truncates, a tab, a word wider than the box, and `push-out` on a balancing paragraph and on a tab paragraph.
- **Push-out checked with a temporary native log** (removed): after each build, the balancing `push-out` paragraph had `lineBreakStrategy` 0 and the tab paragraph still had 1 (`pushOut`).
- **Tab samples checked by forcing it:** with the tab skip disabled (temporary code), both tab samples showed ❌ "stock", so they really test the skip.
- **`adjustsFontSizeToFit` in stock RN:** it scales this 36pt sample down to two small lines even with room for three, with or without a fixed height. That's RN's own scaling; the balanced copy keeps the same scale and line count and balances them.
