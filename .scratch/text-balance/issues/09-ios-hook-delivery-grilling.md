Type: grilling
Status: resolved
Assignee: Sam Jusaitis (claimed)
Blocked by: none

## Question

How should the library ship the iOS balancing hook that tickets 04–06 proved out (swizzling RN's private `-[RCTTextLayoutManager _textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:]`)? Options: swizzle from the library pod with a runtime guard and graceful no-op when the selector or signature changes; ship a `patch-package`/Expo config-plugin patch to RN; upstream an iOS `textBreakStrategy="balanced"` implementation to RN and swizzle only as a polyfill for older versions; or some mix. Decide the delivery mechanism, the supported RN version range, and the failure mode when the hook isn't found.

**Constraint added by Sam (2026-11-17):** the library's `Text` sits alongside RN's `Text` and must not change RN `Text` behaviour. So the iOS trigger can't be `textBreakStrategy="balanced"` alone, because a plain RN `Text` could set it. The question now also covers *how only the library's `Text` reaches the balancing code*: for example, a swizzle gated on a private signal only our component sends, or our own Fabric component that reuses RN's paragraph stack with a `RCTTextLayoutManager` subclass (no swizzle). Facts: [research/ios-isolation-options.md](../research/ios-isolation-options.md); RN history: the selector has been unchanged from 0.76 to main, prebuilt core has been the default since 0.84 (so an RN source patch doesn't compile unless the app builds from source), and Expo SDK 53–58 pair with RN 0.79/0.81/0.83/0.85/0.86/0.88.

## Grilling notes (round 1, Sam)

- Prop name: `balance` (as in the map).
- "Don't change RN's `Text`" means **no modification of RN's classes at all**, not even an invisible gated swizzle. That rules out the swizzle; iOS needs its own native component.
- No upstream RN track. Sam expects RN, if anything, to add a `text-wrap: balance`-style style rather than iOS `textBreakStrategy`.
- When the iOS mechanism is unavailable: render plain, unbalanced text; warn once in dev; never crash.
- iOS ships min-raggedness only; on a break-plan mismatch it falls back to stock wrapping (the squeeze is dropped).

## Answer

**iOS ships as the library's own Fabric component built from subclasses of RN's paragraph classes, with no swizzle and no patch to RN.** Sam's decisions, 2026-11-17. RN's own `Text` is never modified, not even by an invisible, gated hook. Recorded in [ADR 0001](../../../docs/adr/0001-ios-polyfill-swizzle.md).

- **Mechanism:**
  - The shadow node subclasses `ParagraphShadowNode` and owns its own `TextLayoutManager`. That subclass replaces the protected `nativeTextLayoutManager_` with an `RCTTextLayoutManager` subclass.
  - The `RCTTextLayoutManager` subclass overrides the private stack builder `_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:`. It calls `super`, which builds the font-scaled stack, then imposes the 08 min-raggedness plan with the `NSTextContainer` subclass.
  - The view subclasses `RCTParagraphComponentView`, and a codegen host component (`BalancedParagraph`) registers it.
  - It has its own measure cache, so it never collides with RN `Text`. RN's view draws and hit-tests through the layout manager stored in state, so our manager covers measure, draw, hit-test and `onTextLayout`. Facts: [research/ios-isolation-options.md](../research/ios-isolation-options.md).
- **JS dispatch in our `Text`:**
  - `balance` false or missing: plain RN `Text` on both platforms.
  - Android: RN `Text` with `textBreakStrategy="balanced"`, plus the `key` remount from 07.
  - iOS: `<BalancedParagraph><Text …>{children}</Text></BalancedParagraph>`, under `unstable_TextAncestorContext`, so the inner `Text` is virtual text.
  - Toggling `balance` on iOS remounts (the component type changes).
- **Algorithm:** min-raggedness only. On a break-plan mismatch (hyphens, CJK, bidi) it falls back to stock wrapping; the squeeze is dropped.
- **Supported range:** RN ≥ 0.85 (Expo SDK 56+), to be confirmed by ticket 10's header diff.
  - A local `verify:matrix` run builds against each supported RN minor plus the next RC (per RN minor, not per Expo SDK; see [13](13-packaging-tooling-grilling.md)).
  - `peerDependencies` has no upper bound; the `verify:matrix` run is the gate.
  - Use `#if` on RN's version macros wherever the C++ APIs differ between minors.
- **Failure modes:**
  - C++ API drift is a compile error, caught by the `verify:matrix` run.
  - If `RCTTextLayoutManager` stops responding to the private selector (checked once at runtime), the override is never called. Our component then lays out as stock and warns once in dev, with no crash and nothing in release.
- **No upstream RN work** and no "future" note. If RN ships a native balance style, this package becomes obsolete and is deprecated.

Unproven until ticket 10: nested `<Text>` children, press handling and highlight, `selectable`, accessibility and inline attachments inside our component; the extra wrapping span; codegen next to the Expo module.
