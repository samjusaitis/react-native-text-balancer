# Map: text-balance

Label: wayfinder:map

## Destination

A hand-off-ready **spec** for `react-native-text-balancer`: a drop-in `Text` (imported as `import { Text } from 'react-native-text-balancer'`) that accepts all core `Text` props plus `balance?: boolean` (default `false`) and balances line breaks like CSS `text-wrap: balance`. The spec covers public API, per-platform strategy, the algorithm, and an **implementation approach** (native module vs. custom native view, which native APIs to lean on). Building the library is out of scope.

## Notes

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
- [08 iOS min-raggedness prototype](issues/08-ios-min-raggedness-prototype.md): iOS uses minimum raggedness, not the max-width squeeze, and offers no option. Per paragraph, a DP over word widths (one `CTLine`) at the full-width line count, imposed by an `NSTextContainer` subclass with per-line widths keyed by line start index. It matches Android `balanced` line for line on the hard samples, balances each paragraph separately, and costs a 0.59ms median vs. the squeeze's 1.26ms. The squeeze is kept only as a fallback if the breaks don't match the plan.

## Not yet specified

- Native module vs. wrapping/subclassing RN's native Text view (Fabric component): iOS mechanism settled (swizzled hook + exclusion-path strip, per 06); still open: swizzle vs. an upstream RN change; also stability of swizzling a private RN selector across versions.
- iOS algorithm detail: Android's balanced evens out all lines (not a max-width squeeze), so decide binary search vs. Knuth-Plass-style minimum raggedness for iOS visual parity (the 04 spike's squeeze leaves monospace text ragged; 05 names a per-line break plan via delegate veto or `NSTextContainer` subclass as the route); caching (~1ms per stack build, recomputed on every measure/draw/hit-test); per-paragraph insets.
- iOS min-raggedness break candidates: only spaces in the 08 spike; hyphens, CJK and bidi-mixed paragraphs need break opportunities that match TextKit's (otherwise they fall back to the squeeze).
- Example app links the package by bun copy (`file:..`), so native edits need a sync; decide link vs. copy when packaging.
- Android re-render bug: `textBreakStrategy` changes not re-applied when toggling back; remount via `key` in the wrapper vs. a native fix (check RN source/version).
- Interaction with other `Text` props: `numberOfLines`, `ellipsizeMode`, `adjustsFontSizeToFit`, `allowFontScaling`, `lineBreakStrategyIOS`, `textBreakStrategy`, RTL/emoji/mixed fonts.
- Behaviour with nested/inline `<Text>` spans (currently out of scope; revisit how to degrade gracefully).
- Cross-platform parity: how close, and whether to normalize Android's behaviour with the custom algorithm.
- Packaging/tooling: library scaffold (e.g. create-react-native-library), codegen, Expo dev build / config plugin support.

## Out of scope

- Implementing the library (destination is the spec).
- Old architecture support.
- Web support.
- Expo Go (dev build / config plugin is fine).
- `balance` on nested/inline `<Text>` spans.
- Guaranteed identical line breaks on iOS and Android.
