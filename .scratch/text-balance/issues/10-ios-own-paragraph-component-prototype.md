Type: prototype
Status: resolved
Assignee: Sam Jusaitis (claimed)
Blocked by: none

## Question

Does the iOS mechanism decided in [09](09-ios-hook-delivery-grilling.md) work end to end, with RN's own `Text` untouched? The mechanism: a codegen host component `BalancedParagraph` whose shadow node subclasses `ParagraphShadowNode` and owns its own `TextLayoutManager` (with `nativeTextLayoutManager_` swapped for an `RCTTextLayoutManager` subclass that overrides `_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:`), plus a view that subclasses `RCTParagraphComponentView`. Port the 08 min-raggedness code (`NSTextContainer` subclass and DP) into the override, without the swizzle. Wiring facts and file:line refs: [research/ios-isolation-options.md](../research/ios-isolation-options.md) §B.

Check, on RN 0.88.1 in the example app:

1. **Isolation:** next to it, a plain RN `<Text textBreakStrategy="balanced">` with the same string and width renders exactly like stock RN (no cache collision, no balancing).
2. **Parity with RN `Text` inside our component:**
   - the JS shape `<BalancedParagraph><Text>{children}</Text></BalancedParagraph>` under `unstable_TextAncestorContext` (no "Text strings must be rendered within a <Text>" error);
   - nested `<Text>` spans with `onPress` and the press highlight;
   - `selectable`, accessibility (VoiceOver reads it, link frames);
   - an inline attachment (`View` in text);
   - `numberOfLines`, `adjustsFontSizeToFit` and `onTextLayout`.
   Note anything Pressability-related that `Text.js` does and the wrapper must reproduce.
3. **Packaging:** a codegen component living next to the existing Expo module in the same package (prebuilt core, Expo SDK 58).
4. **Runtime guard:** if the private selector is missing, the result is stock layout and one dev warning.
5. **RN range:** diff the headers and signatures used (`ParagraphShadowNode`, `BaseParagraphComponentDescriptor`, `TextLayoutManager`, `ParagraphState`, `RCTParagraphComponentView`, the private selector) across RN 0.85, 0.86, 0.88, 0.89 rc and main. Confirm the ≥ 0.85 floor and list where `#if` version guards are needed.

Record per-build cost against 08's 0.59ms median.

## Answer

**The mechanism works: iOS ships `BalancedParagraph`, the library's own Fabric component, as decided in 09.** Sam accepted this on 2026-11-17 after reviewing the results on the iOS Simulator (RN 0.88.1, Expo SDK 58, iOS 27.2 simulator, Debug build). It needs no swizzle, and RN's `Text` is untouched.

How the prototype does it ([ios/BalancedParagraph.mm](../../../ios/BalancedParagraph.mm) on the prototype branch):

- `BalancedParagraphShadowNode : ParagraphShadowNode`. It inherits RN's constructors and hides the static `Name()`/`Handle()` so they return `"BalancedParagraph"`.
- `BalancedTextLayoutManager : TextLayoutManager`. Its constructor replaces the protected `nativeTextLayoutManager_` with `[RCTBalancedTextLayoutManager new]`.
- `BalancedParagraphComponentDescriptor : ConcreteComponentDescriptor<BalancedParagraphShadowNode>`. It is modelled on `BaseParagraphComponentDescriptor`, but it owns its own `BalancedTextLayoutManager` instance, so it has its own measure cache, and it attaches that instance in `adopt()`.
- `RCTBalancedTextLayoutManager : RCTTextLayoutManager`. It overrides the private builder, which is declared in a category, calls `super`, then imposes the 08 min-raggedness plan. The squeeze is gone: on a plan mismatch it puts RN's container back, so the text gets stock wrapping.
- `RCTBalancedParagraphComponentView : RCTParagraphComponentView`. It only overrides `+componentDescriptorProvider`.
- JS: [src/BalancedText.tsx](../../../src/BalancedText.tsx) renders `<BalancedParagraph {paragraph props}><TextAncestorContext value><Text {span props}>{children}</Text></TextAncestorContext></BalancedParagraph>`. The spec is [src/BalancedParagraphNativeComponent.ts](../../../src/BalancedParagraphNativeComponent.ts).

Results:

1. **Isolation: passed.** A plain RN `Text` and an RN `Text` with `textBreakStrategy="balanced"` and `android_hyphenationFrequency="full"` (the 04–08 flags) give identical `onTextLayout` lines in 27/27 sample × width cases. `BalancedParagraph` balances, with the same output as 08.
2. **Parity: passed, with two gaps.**
   - Raw string children logged no "Text strings must be rendered within a <Text>" errors.
   - Nested `onPress` spans:
     - span taps register and off-span taps are ignored;
     - the pressed span gets RN's rounded per-line highlight, hugging the balanced lines;
     - a root `onPress` works.
   - `selectable` shows Copy on long-press.
   - `numberOfLines`: a truncating count stays unbalanced, as in 06, and a count that fits balances.
   - `adjustsFontSizeToFit`, with `numberOfLines=2`, balances after scaling.
   - `onTextLayout` and toggling `balance` (a remount) work.
   - Accessibility, checked from a dump of `accessibilityElements` (VoiceOver itself not run): the labels and traits match stock (64 static text, 2 for a link span, 66 for a pressable root). Link element frames come from the balanced layout.
   - **Gap: the root `onPress` highlight looks different.** Stock draws a square background behind the whole paragraph (`isHighlighted` on the root). Ours draws the inner span's rounded per-line highlight.
   - **Gap: inline attachments are never balanced.** The `CTLine` used for word widths gives the attachment character (U+FFFC) zero width, so every plan mismatches and the text falls back to stock wrapping. It renders exactly like stock.
   - Pressability needs no wrapper code: `Text.js` gives the inner virtual text the same `PressableVirtualText` path, and `RCTParagraphComponentView` routes touches to the span's event emitter. The wrapper must move `Text.js`'s root-only work onto the host:
     - `accessible` defaults to true (iOS), `allowFontScaling` to true, `ellipsizeMode` to `'tail'`;
     - `numberOfLines` is clamped to >= 0;
     - `selectable`, including `style.userSelect`;
     - `accessibilityRole="link"` when pressable;
     - `aria-label` -> `accessibilityLabel`, `id` -> `nativeID`.
3. **Packaging: works, with two package changes.** Without them, Expo autolinking hides the package from RN's dependency list, because it is an Expo module with no React Native config of its own. RN codegen then never reads `codegenConfig`, and the component isn't registered.
   - A `react-native.config.js` with `dependency.platforms.ios: {}` (and `android: null`).
   - The podspec at the package root: RN's resolver only looks there. `expo-module.config.json` points `apple.podspecPath` at it.
   - The pod isn't added twice.
   - Codegen: use `codegenConfig.ios.components.BalancedParagraph.className` and an `interfaceOnly` spec, with `CodegenTypes.*` from `'react-native'`. Arrays in an event payload must be written `{...}[]`: `Readonly<>` and `ReadonlyArray` fail to parse.
4. **Runtime guard: passed.** A prototype launch flag made the guard look for a renamed selector. Result: the hook was unavailable, nothing was balanced, ours matched stock in 27/27 cases, and Metro showed exactly one dev `RCTLogWarn`. The check is `+[RCTTextLayoutManager instancesRespondToSelector:]` in `+initialize`.
5. **RN range: the floor is exactly 0.85.** RN 0.84.1 declares `class ParagraphShadowNode final` (removed upstream in #55634, first released in 0.85.0). Every dependency is the same, with the same signature and access level, in 0.85.3, 0.86.3, 0.87.1, 0.88.1, 0.89.0-rc.1 and `main`. That includes the private selector, which every path sends to `self`. This comes from diffing sources, not building each version.
   - No `#if` guards are needed.
   - Optional: an `#error` below 0.85.
   - Optional: on 0.89+, RN's umbrella headers (`__has_include(<React/RendererCore.h>)`) for apps that set `RN_STRICT_API=1`.
   - The version macros are in `<cxxreact/ReactNativeVersion.h>`. A source checkout of `main` reports 1000.0, so a check on the minor version alone fails there.
   - Behaviour changes in 0.89+ and `main` (layout at `state.layoutSize`, draw with height `CGFLOAT_MAX`) don't affect balancing.

**Cost:** median 0.49ms per stack build (mean 0.54ms, p90 0.88ms, max 4.96ms, n=285), against 08's 0.59ms median.

Prototype code is on the throwaway branch `prototype/10-ios-own-paragraph-component` (commit e1865ed, cut from 08's b7a4acd; not on main):

- Native: `ios/BalancedParagraph.mm`.
- JS: `src/BalancedText.tsx` and `src/BalancedParagraphNativeComponent.ts`.
- Packaging: `react-native.config.js`, the root `ReactNativeTextBalancer.podspec`, and the `codegenConfig` in `package.json`.
- Example app: three rows per sample (isolation) and the parity probes in `example/App.tsx`.

Gotcha: `simctl` screenshots can lag one action behind, so wait about a second after a tap before taking one.
