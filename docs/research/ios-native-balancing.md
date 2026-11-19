# iOS native text balancing and the RN Fabric text pipeline

> A design-time research note, kept as written. Numbers like 04, 08 or 10 name the prototypes listed in [the research index](README.md#prototypes). What shipped is in [the ADRs](../adr/).

Date researched: 2026-11-17. Question: does iOS have built-in layout that achieves CSS `text-wrap: balance`, and where could a custom width be injected in React Native's Fabric iOS text pipeline?

## Verdict

- **No public iOS API balances lines.** I found nothing in TextKit 1, TextKit 2, NSParagraphStyle, UILabel, UITextView, Core Text, or SwiftUI `Text`, including the iOS 26 and WWDC26 material I could find. This is absence of evidence in the docs I fetched. It is not a documented statement that no such API exists.
- The nearest feature is `NSParagraphStyle.LineBreakStrategy.pushOut`. It avoids a lone orphan word on the last line. That is not balancing. It does not equalize line lengths.
- **Best injection point:** compute a narrower width in the library (binary search on measured line count and widths), then lay out and draw at that width. Details are in "Injection points" below.

## 1. Built-in APIs checked

### NSParagraphStyle.LineBreakStrategy

Source: [NSParagraphStyle.LineBreakStrategy (AppKit page, Apple doc JSON)](https://developer.apple.com/tutorials/data/documentation/appkit/nsparagraphstyle/linebreakstrategy-swift.struct.md)

Options as documented:
- `pushOut`: "The text system pushes out individual lines to avoid an orphan word on the last line of the paragraph."
- `hangulWordPriority`: "The text system prohibits breaking between Hangul characters."
- `standard`: "The text system uses the same configuration of line-break strategies that it uses for standard UI labels."
- `NSLineBreakStrategyNone`: "The text system doesn't use any line-break strategies."

Availability: the UILabel page lists iOS 14.0 ([UILabel.lineBreakStrategy](https://developer.apple.com/documentation/uikit/uilabel/linebreakstrategy.md)). Its default is `standard`. That page also says that when a label has an attributed string, the label's own `lineBreakStrategy` is ignored and you must set it in the paragraph style.

Conclusion: this is an orphan-avoidance heuristic with no tunable target width. The docs do not describe an algorithm, so I can't say how far it moves words.

### SwiftUI Text

Source: [Text (Apple doc JSON)](https://developer.apple.com/documentation/swiftui/text.md)

The "Fitting text into available space" topics list only `textScale` and `TruncationMode`. The overview names `lineLimit`, `allowsTightening`, `minimumScaleFactor` and `truncationMode` as the fit modifiers. No balance, wrap-mode or orphan API appears. I did not find a `lineHeight(_:)` entry on this page. A third-party source says iOS 26 added it, but it controls baseline spacing, not wrapping.

Third-party only (not Apple, treat as unverified): [Fatbobman, "Controlling Orphans in SwiftUI Text"](https://fatbobman.com/en/posts/controlling-orphans-in-swiftui-text/) reports an undocumented `avoidsOrphans` in SwiftUI. I did not fetch or verify it.

### TextKit 1 (NSLayoutManager)

Source: [layoutManager(_:shouldBreakLineByWordBeforeCharacterAt:)](https://developer.apple.com/documentation/uikit/nslayoutmanagerdelegate/layoutmanager(_:shouldbreaklinebywordbeforecharacterat:).md), iOS 7.0+.

The delegate can reject a word-break candidate: "false if the layout manager should find the next break point opportunity before `charIndex`". This lets you veto breaks but not choose a target width. Balancing through this hook would be a hack: you would need to know the whole paragraph's break plan ahead of time.

### TextKit 2 (NSTextLayoutManager)

Source: [NSTextLayoutManagerDelegate](https://developer.apple.com/documentation/uikit/nstextlayoutmanagerdelegate.md), iOS 15.0+.

Hooks: `textLayoutManager(_:shouldBreakLineBefore:hyphenating:)` ("determine the soft line break point"), `textLayoutManager(_:textLayoutFragmentFor:in:)` (custom layout fragment), and link-attribute and attachment-provider hooks. Same limitation as TextKit 1: veto per break, no balance. `UITextView.textLayoutManager` is iOS 16.0+ ([doc](https://developer.apple.com/documentation/uikit/uitextview/textlayoutmanager.md)).

WWDC26 session 370, [Elevate your app's text experience with TextKit](https://developer.apple.com/videos/play/wwdc2026/370/): the page summary I retrieved covers viewport rendering surfaces, extending UITextView and collapsible sections. It lists no line breaking or balancing content. I read a summary of the page, not the transcript.

### Core Text

Source: [CTTypesetterSuggestLineBreak](https://developer.apple.com/documentation/coretext/cttypesettersuggestlinebreak(_:_:_:).md), iOS 3.2+.

"Suggests a contextual line breakpoint based on the width provided." It returns the character count from `startIndex` that fits in `width`. It is a greedy per-line primitive. There is also `CTTypesetterSuggestLineBreakWithOffset` and `CTTypesetterCreateLine`. You could implement balancing on top of it (try a width, step through the lines, compare), but Core Text will not do it for you.

### UILabel and UITextView

- UILabel: `lineBreakStrategy` is the only break control (see above).
- UITextView: backed by TextKit; `textLayoutManager` from iOS 16. No balance API found.

### Paragraph-level width levers (useful for emulation)

- [NSParagraphStyle.tailIndent](https://developer.apple.com/documentation/uikit/nsparagraphstyle/tailindent.md): "If 0 or negative, it's the distance from the trailing margin." A negative `tailIndent` narrows the wrap width inside the same container. Example from the doc: head 0.25 and tail -0.25 give a quarter-inch margin. This is a candidate injection mechanism that stays inside the attributed string.
- [NSTextContainer.lineFragmentPadding](https://developer.apple.com/documentation/uikit/nstextcontainer/linefragmentpadding.md): default 5.0, and the doc says it is not designed to express margins.

## 2. How React Native Fabric (iOS) measures and draws text

All code below is from `facebook/react-native` `main`. I read these files through a fetch tool that summarizes the content, so the behavior descriptions are accurate to the summaries but quoted fragments and any line numbers should be re-checked in the repo before relying on them.

Files:
- [ParagraphShadowNode.cpp](https://raw.githubusercontent.com/facebook/react-native/main/packages/react-native/ReactCommon/react/renderer/components/text/ParagraphShadowNode.cpp)
- [TextLayoutManager.mm](https://raw.githubusercontent.com/facebook/react-native/main/packages/react-native/ReactCommon/react/renderer/textlayoutmanager/platform/ios/react/renderer/textlayoutmanager/TextLayoutManager.mm)
- [RCTTextLayoutManager.mm](https://raw.githubusercontent.com/facebook/react-native/main/packages/react-native/ReactCommon/react/renderer/textlayoutmanager/platform/ios/react/renderer/textlayoutmanager/RCTTextLayoutManager.mm)
- [RCTAttributedTextUtils.mm](https://raw.githubusercontent.com/facebook/react-native/main/packages/react-native/ReactCommon/react/renderer/textlayoutmanager/platform/ios/react/renderer/textlayoutmanager/RCTAttributedTextUtils.mm)
- [RCTParagraphComponentView.mm](https://raw.githubusercontent.com/facebook/react-native/main/packages/react-native/React/Fabric/Mounting/ComponentViews/Text/RCTParagraphComponentView.mm)

### Pipeline

1. **Yoga measure (C++).** `ParagraphShadowNode::measureContent` receives `LayoutConstraints` (min/max size, direction). It looks for a cached layout with equal constraints and point scale. On a miss it builds content and calls `textLayoutManager_->measure(...)` (or the prepared-layout path when `enablePreparedTextLayout` is on). In `layout()`, min and max are both set to the content size, so text is laid out at exactly the size Yoga assigned.
2. **`TextLayoutManager::measure` (ObjC++ bridge).** Gets the `RCTTextLayoutManager`, uses a cache keyed on attributed string, paragraph attributes, layout constraints and point scale, then calls `measureAttributedString:...`. The result is clamped with `layoutConstraints.clamp(measurement.size)`.
3. **`RCTTextLayoutManager` measure.** Converts to `NSAttributedString`, builds a TextKit 1 stack in `_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:`:
   - `NSTextContainer initWithSize:size` with `lineFragmentPadding = 0`
   - `NSLayoutManager` with `usesFontLeading = NO`
   - `NSTextStorage initWithAttributedString:`, then `RCTApplyBaselineOffset`
   Measurement passes `{maximumSize.width, CGFLOAT_MAX}`, calls `ensureLayoutForTextContainer:`, takes height from `usedRectForTextContainer:` (or enumerated line fragments if `maximumNumberOfLines` is set), and rounds to the pixel grid. In auto-width mode, if text wraps, width becomes the container width.
4. **Drawing.** `RCTParagraphComponentView` hosts an `RCTParagraphTextView` as `contentView`. Its `drawRect:` calls `-[RCTTextLayoutManager drawAttributedString:paragraphAttributes:frame:drawHighlightPath:]`. That builds the same stack from the view's frame, then runs `drawBackgroundForGlyphRange:` and `drawGlyphsForGlyphRange:` at `frame.origin`. `RCTTextLayoutSizeForFrameSize` uses the frame width with unbounded height, unless `adjustsFontSizeToFit` is set.
5. **State.** `ParagraphState` carries the attributed string, paragraph attributes, layout manager and measured layout or layout size. `updateState` redraws when the attributed string or paragraph attributes change, or if there are attachments. `updateLayoutMetrics` redraws on size, content frame or scale change.
6. **Other consumers of the same layout.** Hit testing (`getEventEmitterWithAttributeString:...atPoint:`), accessibility, and `getLinesForAttributedString:paragraphAttributes:size:` (the `onTextLayout` data, via `measureLines` in `TextLayoutManager.mm`) all rebuild the TextKit stack from attributed string plus size. A width trick must be applied consistently to every path or hit-testing and `onTextLayout` will disagree with drawing.

Important facts:
- **Fabric iOS text uses TextKit 1** (`NSLayoutManager`, `NSTextStorage`, `NSTextContainer`), not TextKit 2.
- **RN already maps `lineBreakStrategy`.** `RCTNSTextAttributesFromTextAttributes` sets `paragraphStyle.lineBreakStrategy` when the attribute is present. The JS prop is `lineBreakStrategyIOS` with values `none`, `standard`, `hangul-word`, `push-out`, default `none` ([RN Text docs](https://reactnative.dev/docs/text#lineBreakStrategyIOS)).
- RN's own Android prop `textBreakStrategy` accepts `balanced` ([same page](https://reactnative.dev/docs/text#lineBreakStrategyIOS)). There is no iOS equivalent.
- Paragraph style properties RN sets: alignment (RTL-resolved), `baseWritingDirection`, `lineBreakStrategy`, `lineBreakMode`, and `minimumLineHeight`/`maximumLineHeight`.

## 3. Injection points for a custom width

Ranked by how much it avoids forking React Native.

1. **Negative `tailIndent` on the attributed string's paragraph style (smallest change).** Because both measure and draw rebuild their TextKit stack from the same `NSAttributedString`, a `tailIndent` carried in the paragraph style narrows the wrap width in measure, draw, hit-test and `getLines` uniformly. The container, and so the Yoga box, stays full width, which matches CSS balance (box width is unchanged, only the wrap width shrinks). Caveat: RN builds the paragraph style in `RCTNSTextAttributesFromTextAttributes` and does not expose `tailIndent` today, so the library would need its own attribute path or a patch there. Unverified: whether RN's paragraph-style construction preserves a custom `tailIndent` carried through an opaque `NSAttributedString` box (the `OpaquePointer` mode in `TextLayoutManager::measure` and `RCTNSAttributedStringFromAttributedStringBox`). That mode is the likeliest hook and needs a spike.
2. **Custom component view that owns drawing.** Write a Fabric component that measures with its own `NSTextContainer` width (found by search) and draws via TextKit. Full control and no RN patching, but it loses RN's nested `<Text>`, press handling, accessibility and attachment support unless reimplemented.
3. **Patch or subclass `RCTTextLayoutManager`.** Override `_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:` to shrink `size.width` when a paragraph attribute asks for balance. This is the single place where measure, draw and line queries all converge, but it requires modifying RN internals (or patching RN in the app) and re-applying on upgrades. Paragraph attributes (`ParagraphAttributes`) would need a new field and a props-to-attributes plumb in C++.
4. **Constrain from JS (`onTextLayout` + width).** Measure via `onTextLayout` and set `maxWidth` on the Text. Works with no native code, but needs a render pass per search step and changes the Yoga box width, which is not CSS-equivalent (the box shrinks, so alignment and background differ).

Search algorithm (any option): find the minimal wrap width that keeps the same line count as the full width. Measure with `ensureLayoutForTextContainer:` plus line-fragment enumeration (TextKit 1) or `CTTypesetterSuggestLineBreak` loops (Core Text). A binary search over width is O(log W) layouts per text, which matters because `measureContent` runs on the Yoga thread and its results are cached per constraints.

## 4. Gaps and unverified items

- Exact behavior of `pushOut` (how many words move, which lines) is undocumented in what I fetched. Could be tested empirically.
- I did not fetch WWDC transcripts for sessions 10058 (WWDC23), WWDC21 "Meet TextKit 2" or WWDC22 "What's new in TextKit and text views". The only evidence about newer iOS versions is the Apple doc pages above plus the WWDC26 session 370 page summary.
- SwiftUI `Text` internals are closed, so whether it silently balances anything is unknown. The documented API surface has no balancing control.
- RN source was read through summaries. Re-verify symbol names against the repo at the RN version you target (the `main` branch changes quickly, for example `enablePreparedTextLayout`).
