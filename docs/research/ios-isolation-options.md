# Isolating balancing from RN's own Text (iOS, RN 0.88.1)

> A design-time research note, kept as written. Numbers like 04, 08 or 10 name the prototypes listed in [the research index](README.md#prototypes). What shipped is in [the ADRs](../adr/).

Paths are relative to `example/node_modules/react-native/` unless noted. RN = `ReactCommon/react/renderer/`.

## A. Private-signal gating (keep the swizzle)

The hook gets `ParagraphAttributes` by value (`RCTTextLayoutManager.mm:418`). Measure, draw and hit-test all reach it with the paragraph attributes stored in state, so a signal in `ParagraphAttributes` is seen the same way everywhere.

**Cache facts.** `TextMeasureCacheKey ==` compares only the layout-wise attributed string and the full `ParagraphAttributes ==`, plus constraints (`RN/textlayoutmanager/TextMeasureCache.h:262-266`). The layout-wise fragment comparison uses only the string, the font and spacing attributes, and attachment metrics (`:118-145`, `:175-182`). Tag, event emitter, colour and accessibility are not in the key. There is one `TextLayoutManager`, and so one cache, shared by every paragraph (`RN/components/text/BaseParagraphComponentDescriptor.h:25,47-48`).

| Option | Facts | Robustness |
|---|---|---|
| **A1. Sentinel `minimumFontScale`** (for example `-1` or `0.000123`, set by our wrapper on iOS only) | Parsed into `ParagraphAttributes` (`RN/attributedstring/conversions.h:1038-1043`). Included in `==` (`ParagraphAttributes.cpp:36`) and in the hash (`ParagraphAttributes.h:111`), so balanced and plain renders cannot collide in the cache. Forwarded by RN Text (`Libraries/Text/TextNativeComponent.js:45`). **No iOS Fabric code reads it.** Only `minimumFontSize`/`maximumFontSize` are used (`RCTTextLayoutManager.mm:440-443`); a grep of ReactCommon/React finds no other reader. Android does read it (`ViewProps.kt:101`), so set it on iOS only. | **Good.** A plain Text would need that exact nonsensical value. Risk: RN later implements `minimumFontScale` on iOS Fabric (it is a documented iOS prop). A negative sentinel would then need clamping. Our users lose nothing, because the prop is already a no-op there. |
| A2. `includeFontPadding`, `textAlignVertical`, `android_hyphenationFrequency` | In `ParagraphAttributes` and its `==`. Ignored on iOS. | **Poor.** Cross-platform styles set these often (`includeFontPadding:false` is common), so a plain Text can easily produce them. |
| A3. Native registry keyed by react tag or event emitter (`RCTAttributedStringEventEmitterKey`, `RCTAttributedTextUtils.h:17`) | The attribute does reach the NSAttributedString. But it is **not in the measure cache key**, so a plain Text with the same string, attributes and width gets the cached balanced size, or the reverse. Draw (uncached) would then disagree with the measured size. Registry lifetime also has to track clones and unmounts. | **Unsafe. Blocker:** cache collision. |
| A4. Custom TextAttributes value | Only layout-wise fields are in the key. Abusing one of them (for example a tiny `letterSpacing`) changes layout. | Poor. |

## B. Own Fabric component reusing the paragraph stack

**Headers are present in the prebuilt pods.** `Pods/React-Core-prebuilt/Headers/react/renderer/components/text/{ParagraphShadowNode,ParagraphComponentDescriptor,ParagraphState,BaseTextShadowNode,ParagraphProps}.h` and `.../textlayoutmanager/{TextLayoutManager,RCTTextLayoutManager,RCTAttributedTextUtils}.h` exist. `RCTParagraphComponentView.h` is in `React.xcframework/*/React.framework/Headers/`.

**Symbols are exported** from the dynamic `React.framework` (nm, simulator slice): `TextLayoutManager::TextLayoutManager`, `::measure`, the `ParagraphShadowNode` constructors, `setTextLayoutManager`, `measureContent`, `layout`, its vtable and typeinfo, `ParagraphComponentName`, `_OBJC_CLASS_$_RCTParagraphComponentView`, `_OBJC_CLASS_$_RCTTextLayoutManager`.

**Wiring:**
- `ParagraphShadowNode` is not `final` (`ParagraphShadowNode.h:31`). `Name()`/`Handle()` are static (`RN/core/ConcreteShadowNode.h:55-63`), so a subclass can hide them to return `"BalancedParagraph"`. `ParagraphComponentDescriptor` is `final` (`ParagraphComponentDescriptor.h:19`), so write your own descriptor, modelled on `BaseParagraphComponentDescriptor`. `adopt()` calls `setTextLayoutManager(...)` (`BaseParagraphComponentDescriptor.h:36-44`). Pass **our own `TextLayoutManager` instance**, not the shared `TextLayoutManagerKey` one.
- `TextLayoutManager` hard-codes `[RCTTextLayoutManager new]` (`.../ios/.../TextLayoutManager.mm:19`), but `nativeTextLayoutManager_` is `protected` (`TextLayoutManager.h:66`). A subclass constructor can replace it with `[RCTBalancedTextLayoutManager new]`. That ObjC subclass overrides `_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:` (private; declare it in a category). It is called via `self` (`RCTTextLayoutManager.mm:54,86,136,371,455,486`), so normal dispatch works and **no swizzle is needed**. `measure()` is non-virtual but goes through `nativeTextLayoutManager_` (`TextLayoutManager.mm:34`). The instance gets its own cache (`TextLayoutManager.h:67`), so there is **no collision with RN Text**.
- State carries the layout-manager pointer. `updateStateIfNeeded` stores `textLayoutManager_` (`ParagraphShadowNode.cpp:160-182`). `RCTParagraphComponentView` draws, hit-tests and builds a11y through `stateData.layoutManager.lock()->getNativeTextLayoutManager()` (`RCTParagraphComponentView.mm:183-186,239-246,309-316,445-451`). So draw and touch use our manager automatically.
- View: subclass `RCTParagraphComponentView` and override `+componentDescriptorProvider` (`RCTParagraphComponentView.mm:105-107`). Its state casts target `ParagraphShadowNode::ConcreteState` (`:138,146`). That is the same `ConcreteState<ParagraphState>` type, so the casts stay valid. Register it with codegen `ios.componentProvider` or `RCTComponentViewFactory registerComponentViewClass:`. RN's own registration maps only `"Paragraph"` (`React/Fabric/Mounting/ComponentViews/RCTFabricComponentsPlugins.mm:24`; `RN/componentregistry/componentNameByReactViewName.cpp:28`).
- Nested children: `BaseTextShadowNode::buildAttributedString` is generic over Text/RawText children, so it is inherited.

**JS side:**
- `unstable_TextAncestorContext` is a public export (`index.js:150-151`). Wrapping children in `value={true}` makes nested RN `<Text>` render `NativeVirtualText` (`Libraries/Text/Text.js:268-281`).
- **Gotcha:** the Fabric renderer sets `isInAParentText` only for hard-coded host names (`RCTText`, `RCTVirtualText`, `RCTSelectableText`, …) (`Libraries/Renderer/implementations/ReactFabric-dev.js:2846-2852`). Raw strings directly under `BalancedParagraph` log "Text strings must be rendered within a <Text>" (`:17180-17183`; it is `console.error` in dev, not a throw). Workaround: always render `<BalancedParagraph><Text>{children}</Text></BalancedParagraph>`. This adds one span, and the inner Text then becomes virtual text.
- View config: `codegenNativeComponent` (public, `index.js:255`) with `interfaceOnly: true` (`Libraries/Utilities/codegenNativeComponent.js:20`) can declare the paragraph props, and the base config already carries `style` (`Libraries/NativeComponent/BaseViewConfig.ios.js:377`). The alternative is to copy `textViewConfig` (`TextNativeComponent.js:32-56`).
- Pressability, `selectable` (`RCTSelectableText`) and highlighting from `Text.js` must be re-implemented or delegated to the inner Text.

**Risks:**
- Subclassing internal C++ classes makes the C++ ABI and layout depend on the exact RN version.
- An Expo Modules-API view cannot host a custom shadow node, so the component needs a plain RN codegen component in the package.
- I did not verify any existing third-party lib that uses this pattern in this pass.

## C. Other routes

- **C1 (A1 plus B-lite):** keep RN's `Paragraph` and the swizzle, gated on A1. This needs the least code.
- **C2:** gate the swizzle on `self != RCTTextLayoutManager` and use B's `TextLayoutManager` subclass. Only our instance balances, but this still needs B's shadow node and descriptor, so it adds nothing over B.
- **C3:** fully own text rendering (as react-native-uitextview does, from memory). That loses RN parity and costs much more.
