Type: research
Status: resolved
Assignee: Sam Jusaitis (claimed, research subagent)
Blocked by: 04

## Question

Which iOS approaches can balance RN Fabric `Text` line breaks **without** the two trade-offs found in [04 iOS tailIndent injection prototype](04-ios-tailindent-injection-prototype.md): (1) the pressed nested-span highlight extending to the box edge past the narrowed line, and (2) no support for `adjustsFontSizeToFit` (RN scales fonts inside `_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:`)?

Survey and rank candidates against RN 0.88.1's iOS text code (`RCTTextLayoutManager.mm`, `RCTParagraphComponentView.mm`, `RCTAttributedTextUtils.mm`), for example:

- Where the highlight path comes from (`getRectWithAttributedString:` / `enumerateEnclosingRectsForGlyphRange:` / `RCTParagraphComponentView` highlight drawing) and whether it can be clipped to used rects under `tailIndent`.
- Narrowing the `NSTextContainer` width (instead of `tailIndent`) and offsetting the draw origin, or `exclusionPaths`, `NSLayoutManagerDelegate` line-fragment hooks (`shouldSetLineFragmentRect:...`), or a custom `NSTextContainer` subclass (`lineFragmentRectForProposedRect:`).
- Balancing **after** `scaleFontSizeToFitSize:` (wrap the original then re-balance), and how `adjustsFontSizeToFit` + balance should interact (CSS has no analogue).
- Whether any approach also enables minimum-raggedness (Knuth-Plass-like) breaking, for parity with Android's `balanced`.
- Hook surface: swizzling the private selector vs. a public/stable seam (subclassing `RCTParagraphComponentView`, a custom Fabric component, an RN patch or upstream `ParagraphAttributes` field).

Answer: a ranked shortlist with the trade-offs each removes or introduces, ready to prototype. Cite RN source at the 0.88.1 tag and Apple docs.

## Answer

Keep the swizzled `_textStorageAndLayoutManagerWithAttributesString:...` hook, but balance **after** RN's `scaleFontSizeToFitSize:` and narrow with **`NSTextContainer.exclusionPaths`** (a trailing strip; both sides for centred text) instead of `tailIndent`.

- Highlight: RN builds it from `enumerateEnclosingRectsForGlyphRange:withinSelectedGlyphRange:` (selection rects). For a span that wraps, those rects run to the end of the line fragment. `tailIndent` leaves the fragments full-width; exclusion paths narrow them, so the highlight should stop at the balanced edge.
- `adjustsFontSizeToFit`: balancing keeps the line count, so the scaled text still fits. Skip balancing when `numberOfLines` truncates.
- Min-raggedness (Android `balanced` parity): impose a per-line break plan, either with the `shouldBreakLineByWordBeforeCharacterAtIndex:` delegate veto or with an `NSTextContainer` subclass overriding `lineFragmentRectForProposedRect:`.
- Endgame: upstream the same change to RN, keyed on the already-parsed `textBreakStrategy`.

Nothing was run, so all of this needs a spike to confirm. Ranked shortlist, trade-offs and RN 0.88.1 line refs: [research/ios-balancing-alternatives.md](../research/ios-balancing-alternatives.md).
