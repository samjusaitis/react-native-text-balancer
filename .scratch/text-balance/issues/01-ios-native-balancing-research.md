Type: research
Status: resolved
Blocked by: none

## Question

Does iOS have any built-in text-layout functionality that achieves a `text-wrap: balance` effect? Cover TextKit 1 and 2, `NSParagraphStyle`, `NSLineBreakStrategy`, Core Text / `CTTypesetter`, `UILabel`/`UITextView`, and anything new in recent iOS versions (including SwiftUI `Text`). Also report how React Native's iOS Text pipeline (`RCTTextLayoutManager`, `NSTextStorage`, Fabric's `RCTParagraphComponentView`) measures and draws text, i.e. where a custom width could be injected. Cite primary sources.

## Answer

No public iOS API balances lines (TextKit 1/2, NSParagraphStyle, UILabel/UITextView, Core Text, SwiftUI Text); absence in the docs fetched, not a documented "no". Closest is `NSParagraphStyle.LineBreakStrategy.pushOut` (iOS 14+), which only avoids a last-line orphan. Delegate hooks only veto breaks; `CTTypesetterSuggestLineBreak` is a greedy primitive to build on.

RN Fabric iOS text uses a TextKit 1 stack rebuilt per measure/draw/hit-test/`onTextLayout` call (`RCTTextLayoutManager`), all from the attributed string plus a size.

Best injection point: binary-search the minimal width keeping the full-width line count, apply it via negative `NSParagraphStyle.tailIndent` on the attributed string (Yoga box stays full width, like CSS balance). RN doesn't expose `tailIndent`, so it needs an attribute path or patch; unverified whether RN preserves it in the opaque NSAttributedString box. Fallbacks: (a) patch `_textStorageAndLayoutManagerWithAttributesString:...size:`, (b) custom Fabric component (loses nested Text/press/a11y), (c) JS `onTextLayout` + maxWidth (not CSS-equivalent).

Full findings: [research/ios-native-balancing.md](../research/ios-native-balancing.md). RN source was read via a summarizing fetch; re-verify symbols at the target RN version.
