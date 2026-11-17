Type: prototype
Status: open
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
