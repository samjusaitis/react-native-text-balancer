Type: grilling
Status: resolved
Assignee: Sam Jusaitis (claimed)
Blocked by: none

## Question

What exactly does the public API promise? Pin down `<Text balance>` semantics for the spec:

- **Conflicting or related props:** `textBreakStrategy` (user-set on Android, and when `balance` is on), `lineBreakStrategyIOS`, `ellipsizeMode`/`numberOfLines` (10: balanced to the visible count, skipped when it truncates), `adjustsFontSizeToFit`, `allowFontScaling`/`maxFontSizeMultiplier`.
- **Nested `<Text>`:** `balance` on a nested span is out of scope; is it ignored silently, warned in dev, or typed out?
- **Fallback behaviour** users should expect (attachments, unsupported scripts, missing private selector): stock wrapping, documented and/or warned.
- **Cross-platform parity promise:** both platforms aim for minimum raggedness (Android native `balanced`, iOS DP); what the docs promise when line breaks differ.
- **iOS root `onPress` highlight:** match stock's square paragraph highlight (press state on the host) or accept the span-style highlight from 10.
- The `ref` and the type surface (does `Text` from the package re-export `TextProps` + `balance`, and `forwardRef` to the host?).

## Answer

**`balance` is a best-effort prop on the outermost `Text`. When it can't balance a paragraph, that paragraph renders with stock wrapping, never clipped or broken.** Sam's decisions, 2026-11-17. Terms are in [GLOSSARY.md](../../../GLOSSARY.md).

- **Types and exports:** the package exports only `Text` and `TextProps`. There's no default export and nothing else from RN is re-exported.
  - `TextProps = Omit<RN.TextProps, 'textBreakStrategy'> & { balance?: boolean }`, with `balance` defaulting to `false`.
  - `ref` is a plain prop (React 19, so no `forwardRef`). It has the same type as RN `Text`'s `ref` and points at the native host: RN `Text` on Android or when `balance` is off, and the `BalancedParagraph` host on iOS. Because toggling `balance` remounts, the `ref` changes when it toggles.
- **`textBreakStrategy`:** removed from the public API, and stripped at runtime if it's passed anyway (plain JS or a cast), silently. On Android the wrapper owns it: `balanced` when `balance` is on, RN's default (`highQuality`) when it's off. This is the one exception to "`balance` off renders exactly like RN `Text`".
- **`lineBreakStrategyIOS`** (amended 2026-11-18, ticket 15): the push-out part is removed only on paragraphs where the balanced plan is actually applied, because it fights the plan. The swizzle clears `pushOut` from the paragraph style, lays out the plan and checks it. If the paragraph falls back to stock wrapping, the original style is restored, so the user's `push-out` still prevents orphans there. There's no dev warning, because nothing the user asked for is lost. Balancing usually prevents a last-line orphan, but not always: a fallback paragraph, or break points that force one (a long unbreakable word that nearly fills the line), can still leave one. _Originally:_ push-out dropped whenever `balance` was on, with one dev warning.
- **`numberOfLines` / `ellipsizeMode`:** if the text fits within `numberOfLines`, it's balanced to that many lines. If it truncates, line breaks follow the platform: stock on iOS, and on Android whatever native `balanced` does with `maxLines`, which isn't tested yet (a test-app check, not a promise). `ellipsizeMode` is unaffected.
- **`adjustsFontSizeToFit`, `allowFontScaling`, `maxFontSizeMultiplier`:** stock meaning and defaults; balancing runs on the final scaled text. On iOS the wrapper moves these, along with the other root-only `Text.js` defaults from ticket 10, onto `BalancedParagraph`.
- **Nested `Text`:** a nested library `Text` always renders as a plain RN span, and `balance` on it is ignored silently. The docs say that `balance` on a nested `Text` has no effect.
- **Fallback contract:**
  - The fallback is per paragraph: the other paragraphs still balance.
  - Content-dependent fallbacks are silent. The README lists them: text that truncates, tabs, a word wider than the box (no plan fits), and break disagreements that one repair can't fix. Thai-family scripts and kinsoku are listed as "may fall back".
  - The README lists these as balanced (ticket 11): inline attachments, bidi text, CJK, Korean, and explicit and soft hyphens.
  - Only the environment fallback warns: a missing private selector gives one dev warning.
  - There's no "did it balance" API in v1.
- **Parity promise:** both platforms minimise raggedness. Line breaks can differ between iOS and Android because of fonts and text engines, and identical breaks aren't guaranteed.
- **iOS root `onPress` highlight:** the span-style highlight from ticket 10 (rounded, hugging each line) is accepted and documented as a known difference from stock's square paragraph highlight. Pressability stays on the inner virtual `Text`.
