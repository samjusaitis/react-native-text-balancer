Type: grilling
Status: resolved
Assignee: Sam Jusaitis (claimed)
Blocked by: none

## Question

How should the library be delivered? The current route is a published package with its own `Text` and a `balance` prop, rendered on iOS by our own component (ticket 09). The alternative is a swizzle that makes iOS honour RN's existing `textBreakStrategy="balanced"`. The library is primarily for Sam's own handful of apps.

## Answer

**The library is a polyfill: installing it makes RN's own `textBreakStrategy="balanced"` balance on iOS, as it already does on Android.** It has no `Text` component and no `balance` prop. Sam decided this on 2026-11-18, and it replaces the own-component decision in [ADR 0001](../../../docs/adr/0001-ios-polyfill-swizzle.md), which is rewritten for the polyfill.

- **Why the earlier isolation rule no longer applies:** we built our own component only so a plain RN `Text` with `textBreakStrategy="balanced"` would stay stock on iOS, which protects apps that didn't ask for balancing. A package whose whole job is to make that prop work on iOS is opted into by installing it. If a third-party component sets `balanced`, it starts balancing on iOS too, and that's the intended behaviour.
- **iOS mechanism:** swizzle the private `-[RCTTextLayoutManager _textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:]` from `+load`, as tickets 04, 06 and 08 did. Run only when `paragraphAttributes.textBreakStrategy == Balanced`, after RN's font scaling. Apply the min-raggedness plan through the `NSTextContainer` subclass from [08](08-ios-min-raggedness-prototype.md), using [11](11-ios-plan-inputs-research.md)'s plan inputs as verified by [14](14-ios-plan-inputs-on-device-prototype.md). RN's measure cache already keys on `ParagraphAttributes`, so balanced and stock layouts don't collide (04).
- **Guard:** if the selector is missing, or its type encoding doesn't match the expected signature, don't swizzle. The app gets stock layout plus one dev warning. The type-encoding check is new: a renamed parameter type with the same selector would otherwise crash instead of falling back.
- **Android:** the library does nothing. Native `balanced` already works. The re-render bug from [07](07-android-text-break-strategy-rerender-research.md) (switching to `balanced` at runtime doesn't re-apply) is left as RN's own behaviour, and the README tells people to use a `key` if they need it. None of Sam's apps switch it at runtime.
- **API:** none. People write `textBreakStrategy="balanced"`. RN's `TextProps` already types it on every platform (via `TextPropsAndroid`), so no TypeScript ships.
- **Distribution:** a public GitHub repo, installed as a git dependency pinned to a tag (`"react-native-text-balancer": "github:<owner>/react-native-text-balancer#vX.Y.Z"`). It isn't published to npm for now. With no JS to build, a git install needs no `prepare` step, so npm would mostly add semver ranges and discoverability. Publishing can be added later without changing the package. The README must make it usable by anyone: what it does, install, the one prop, the Android `key` note, supported RN range, and what falls back to stock wrapping.
- **Package contents:** `package.json` (`peerDependencies` `react-native >=0.85.0`), the iOS sources, a root podspec, and `react-native.config.js` with `android: null`. It has no codegen, no `src/` and no bob. Bare RN autolinks it through the RN CLI, and Expo dev builds autolink it through prebuild with no config plugin.
- **Verification:** `verify:matrix` (iOS compile per RN minor ≥ 0.85 plus the RC) and the example app's self-checking test screen stay from [13](13-packaging-tooling-grilling.md). The `resolveText` unit tests go, because there's no JS left.

What this supersedes:
- [09](09-ios-hook-delivery-grilling.md): the own-component decision and the `balance` prop.
- [10](10-ios-own-paragraph-component-prototype.md): its component, though the RN-range finding still holds.
- [12](12-public-api-semantics-grilling.md): replaced by "the prop is RN's own". Fallback and best-effort semantics carry over. `push-out` is removed only on paragraphs the plan balances, and restored on fallback, with no warning (Sam, 2026-11-18; see 12's amended `lineBreakStrategyIOS` rule). It doesn't make a paragraph skip balancing.
- [13](13-packaging-tooling-grilling.md): the codegen, bob, `resolveText` and npm `files` parts.
