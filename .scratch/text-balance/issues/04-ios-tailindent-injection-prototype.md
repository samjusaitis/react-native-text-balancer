Type: prototype
Status: resolved
Assignee: Sam Jusaitis (claimed)
Blocked by: 02

## Question

On iOS Fabric, can a balanced width be injected via negative `NSParagraphStyle.tailIndent` so measure, draw, hit-test and `onTextLayout` all honour it? Spike: does RN preserve a custom `tailIndent` carried in the attributed string (including the opaque `NSAttributedString` box in `TextLayoutManager::measure`), or must `RCTTextLayoutManager` be patched / a new `ParagraphAttributes` field added? Also try a native binary-search balancer in the test app and judge the visual result. Informs: native module vs. wrapping RN's Text view. See [iOS research](../research/ios-native-balancing.md).

## Answer

**Yes, a negative `NSParagraphStyle.tailIndent` works as the iOS balancing mechanism** in RN Fabric `Text` (RN 0.88.1, prebuilt core, iOS 27.2 simulator). Measure, draw, hit-test and `onTextLayout` all honour it, with no RN fork. Human-reviewed by Sam.

How the spike injects it:

- The opaque `NSAttributedString` box is irrelevant: `Text` always takes the `Value` path (`RCTNSAttributedStringFromAttributedString`); only TextInput uses the opaque box. A custom `tailIndent` can't ride in from JS.
- All consumers (measure, `drawAttributedString:`, `getEventEmitterWithAttributeString:` hit-test, `getLinesForAttributedString:` / `onTextLayout`, `getRectWithAttributedString:`) build their stack via the private `-[RCTTextLayoutManager _textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:]`. The spike swizzles it from the library's pod.
- Flag: the existing `textBreakStrategy="balanced"` prop. It's Android-documented but parsed into `ParagraphAttributes.textBreakStrategy` on iOS too, so it reaches the hook with no new prop plumbing.
- Algorithm: binary-search (0.5pt) the narrowest width that keeps the full-width line count, apply `tailIndent = -(width - balanced)`; centred text splits the inset into head/tail. The container (and so the Yoga box) stays full width, as CSS balance does.

Observed:

- Orphans removed (e.g. the 240pt centred headline), centring kept, RTL keeps its right edge (the inset lands on the trailing, left side), emoji fine.
- Hit-test correct: only taps on the nested pressable span fire; `onTextLayout` reports the narrowed lines (229/194/200 → 195/223/200).
- Cost: ~1ms per stack build, recomputed on every measure/draw/hit-test call; needs a cache keyed on (string, width).

**Trade-offs (blocking acceptance as the final approach):**

1. **Tap highlight overflows:** the pressed-span highlight extends to the box edge, past the narrowed line.
2. **`adjustsFontSizeToFit` skipped:** RN scales fonts inside the same method; the spike bails out rather than balance after scaling.

Other limits: it's a max-width squeeze, not minimum raggedness (monospace 240pt stays ragged; Android evens all lines). Multi-paragraph text shares one inset. `numberOfLines` untested. Swizzling a private selector is fragile across RN versions.

Prototype code (uncommitted, in the working tree): [ios/PrototypeBalanceSwizzle.mm](../../../ios/PrototypeBalanceSwizzle.mm), `install_modules_dependencies(s)` in the podspec, and the hit-test probe + centred sample in `example/App.tsx`.

Gotchas: `example` installs the package via `file:..`, which bun **copies**, so native edits in `ios/` don't reach the app until synced into `example/node_modules/react-native-text-balancer/ios/` (or the dep switched to a link). Metro was run on port 8100 (`RCT_jsLocation` user default) because 8099 was in use by another project.
