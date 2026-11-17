# Map: text-balance

Label: wayfinder:map

## Destination

A hand-off-ready **spec** for `react-native-text-balancer`: an iOS **polyfill** that makes React Native's own `textBreakStrategy="balanced"` balance line breaks on iOS (Android already does it natively), like CSS `text-wrap: balance`. It's installed from a public GitHub repo, so anyone can understand and use it. The spec covers the iOS mechanism, the algorithm, packaging and verification. Building the library is out of scope.

## Notes

- **Delivery (Sam, 2026-11-18, [15](issues/15-delivery-polyfill-grilling.md)):** polyfill, not a component. The library swizzles RN's iOS text layout so `textBreakStrategy="balanced"` balances; installing it is the opt-in. This replaces the 2026-11-17 isolation rule (own component, RN `Text` untouched).
- New architecture (Fabric/TurboModules) only.
- Balancing is computed natively on both platforms; no JS-side measure loop.
- Android: first test whether `textBreakStrategy="balanced"` is sufficient; otherwise implement natively.
- iOS: lean on native text APIs if any balancing exists; otherwise a custom native algorithm (baseline: binary search on max width as in `react-wrap-balancer`, line count checked via the platform text engine).
- The package includes a simple **test app** (iOS + Android) used first to test Android `textBreakStrategy`, later to test the finished component.
- Cross-platform visual parity is an ideal aim, not essential; checked by humans running the test app on both platforms.
- Consult skills: grilling, domain-modeling (HITL tickets); research (research tickets); prototype (prototype tickets).
- Tracker: local markdown (`.scratch/text-balance/`).

## Decisions so far

<!-- one line per resolved ticket -->

- [01 iOS native balancing research](issues/01-ios-native-balancing-research.md): no native iOS balancing exists; best injection is a negative `tailIndent` from a native binary search over RN's TextKit 1 stack (needs a spike).
- [02 Test app scaffold](issues/02-test-app-scaffold.md): Expo module + dev-client example app at the repo root; run with `bun run ios|android` from `example/`; not yet run on a device.
- [03 Android textBreakStrategy prototype](issues/03-android-text-break-strategy-prototype.md): native `textBreakStrategy="balanced"` is good enough on Android (even distribution across lines, min-raggedness-like); but toggling it back to `balanced` doesn't re-apply, needs a `key` remount workaround.
- [04 iOS tailIndent injection prototype](issues/04-ios-tailindent-injection-prototype.md): negative `tailIndent` works functionally (measure, draw, hit-test, `onTextLayout` agree) via swizzling RN's private text-stack builder, flagged by `textBreakStrategy="balanced"`; trade-offs: tap highlight overflows to the box edge, `adjustsFontSizeToFit` unsupported.
- [05 iOS balancing alternatives research](issues/05-ios-balancing-alternatives-research.md): keep the swizzled hook but balance after RN's font scaling and narrow with `NSTextContainer.exclusionPaths` instead of `tailIndent`, which should fix both trade-offs (unverified, needs a spike); a per-line break plan is the route to min-raggedness; upstreaming to RN is the long-term option.
- [06 iOS exclusionPaths prototype](issues/06-ios-exclusion-paths-prototype.md): exclusion-path strip applied after RN's font scaling fixes both 04 trade-offs (highlight stops at the balanced edge; `adjustsFontSizeToFit` balances, truncating `numberOfLines` is skipped); alignment and RTL correct; ~1ms per build, same as tailIndent; stock RN draws RTL press highlights in the wrong place (character range passed as a glyph range), separate from balancing.
- [07 Android textBreakStrategy re-render research](issues/07-android-text-break-strategy-rerender-research.md): RN's `ParagraphShadowNode::updateStateIfNeeded` skips the state update when only `paragraphAttributes` change, so the view keeps the old break strategy (unfixed upstream as of 0.89 rc); keep an Android-only `key` remount in the wrapper (no upstream fix; see 09).
- [08 iOS min-raggedness prototype](issues/08-ios-min-raggedness-prototype.md): iOS uses minimum raggedness, not the max-width squeeze, and offers no option. Per paragraph, a DP over word widths (one `CTLine`) at the full-width line count, imposed by an `NSTextContainer` subclass with per-line widths keyed by line start index. It matches Android `balanced` line for line on the hard samples, balances each paragraph separately, and costs a 0.59ms median vs. the squeeze's 1.26ms. The squeeze is kept only as a fallback if the breaks don't match the plan.
- [09 iOS hook delivery grilling](issues/09-ios-hook-delivery-grilling.md) _(partly superseded by 15)_: no swizzle and no RN patch. On iOS, `balance` renders the library's own Fabric component (`BalancedParagraph`, built from subclasses of RN's `ParagraphShadowNode`, `TextLayoutManager`, `RCTTextLayoutManager` and `RCTParagraphComponentView`), so RN's `Text` is never touched ([ADR 0001](../../docs/adr/0001-ios-polyfill-swizzle.md)). Prop is `balance`; off means plain RN `Text`. Min-raggedness only, with a stock fallback (the squeeze is dropped). RN ≥ 0.85, gated by a local per-RN-minor build matrix (13). A missing private selector means stock layout plus one dev warning. No upstream RN track.
- [10 iOS own paragraph component prototype](issues/10-ios-own-paragraph-component-prototype.md) _(partly superseded by 15)_: `BalancedParagraph` works end to end on RN 0.88.1 with no swizzle. A plain RN `Text` with `textBreakStrategy="balanced"` renders exactly like stock (27/27 cases). Nested press spans and their highlight, `selectable`, accessibility, `numberOfLines`, `adjustsFontSizeToFit` and `onTextLayout` match RN `Text`. The guard gives stock layout plus one dev warning. Packaging needs `react-native.config.js` plus a podspec at the package root so RN codegen sees the Expo module. The floor is exactly RN 0.85 (0.84 has `ParagraphShadowNode final`); nothing changes through 0.89 rc and `main`, so no `#if` guards. It costs a 0.49ms median per build. Two gaps: inline attachments fall back to stock wrapping, and the root-press highlight is the span style.
- [11 iOS plan inputs research](issues/11-ios-plan-inputs-research.md): break candidates from `CFStringTokenizer` line-break units, widths from per-character `CTLine` advances (attachment bounds for U+FFFC, trailing whitespace stripped), DP windowed for CJK, one repair retry before stock fallback; covers Latin, hyphens, CJK, Korean, bidi and attachments. No exact iOS oracle exists (`lineBreakBeforeIndex:` is macOS-only). Tokenizer/TextKit agreement and cost (~0.6ms est.) unverified.
- [12 Public API semantics grilling](issues/12-public-api-semantics-grilling.md) _(partly superseded by 15)_: `balance` is best effort on the outermost `Text`; a paragraph it can't balance gets stock wrapping, silently except one dev warning for a missing selector. Exports only `Text` and `TextProps` (`Omit<RN.TextProps, 'textBreakStrategy'> & { balance?: boolean }`); `textBreakStrategy` is also stripped at runtime and owned by the wrapper on Android. `ref` is a prop that points at the native host. `lineBreakStrategyIOS` push-out is dropped while balancing, with a dev warning. `balance` on a nested `Text` is ignored silently. Fitting `numberOfLines` balances, truncating doesn't (Android truncation is untested). No parity guarantee. The iOS root-press highlight in span style is accepted. Terms are in [GLOSSARY.md](../../GLOSSARY.md).
- [13 Packaging and tooling grilling](issues/13-packaging-tooling-grilling.md) _(partly superseded by 15)_: a plain RN library, not an Expo module (works in bare RN and Expo dev builds, no config plugin): codegen `BalancedParagraph`, root podspec, `react-native.config.js` (`android: null`, no `android/` dir); built with react-native-builder-bob; `peerDependencies` `react-native >=0.85.0`, `react *`; npm `files` allowlist. Example app keeps `file:..` plus a `bun run sync` script. No CI: `bun run check` (`bun test` on a pure `resolveText` dispatch function, `tsc`, `eslint`) on every change; before releases and new RN versions, a local `verify:matrix` (iOS compile per RN minor ≥ 0.85 plus RC, Expo example build) and a self-checking test screen read by a human. Release process left to the implementer.
- [15 Delivery polyfill grilling](issues/15-delivery-polyfill-grilling.md): polyfill, not a component. Installing the package makes RN's own `textBreakStrategy="balanced"` balance on iOS, via the swizzle from 04/06/08 with min-raggedness. The swizzle checks the selector and its type encoding; on a mismatch it gives stock layout plus one dev warning. No JS, no `balance` prop, and Android untouched (use a `key` to re-apply). It's a public GitHub repo installed as a tag-pinned git dependency, not on npm. [ADR 0001](../../docs/adr/0001-ios-polyfill-swizzle.md) is rewritten for the polyfill.

## Not yet specified

- Writing the hand-off spec itself once the remaining tickets resolve: structure, and what goes in it vs. linked from the tickets and ADR.

## Out of scope

- Implementing the library (destination is the spec).
- Old architecture support.
- Web support.
- Expo Go (dev build / config plugin is fine).
- Balancing nested/inline `<Text>` spans (RN only reads `textBreakStrategy` on the outermost `Text`).
- Guaranteed identical line breaks on iOS and Android.
- A "did it balance" API or debug flag (v1).
