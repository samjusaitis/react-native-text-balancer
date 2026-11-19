# Break candidates from `CFStringTokenizer`, widths from `CTRun` advances, checked against TextKit

The library doesn't ask TextKit where it would break. It finds candidates with `CFStringTokenizer` line-break units (UAX #14), measures each segment from logical-order `CTRun` advances of one `CTLine` per paragraph, chooses breaks, lays them out, and checks that TextKit's line starts match. On a mismatch it gets one repair retry, then default wrapping. iOS has no exact TextKit oracle: `-[NSAttributedString lineBreakBeforeIndex:withinRange:]` is macOS-only, and probing TextKit for every candidate line costs tens of milliseconds. Over about 1,700 builds across Latin, hyphens, CJK, Korean, Thai, Arabic with English and inline views, the tokenizer and TextKit never disagreed (branch `prototype/14-ios-plan-inputs-on-device`; research in [iOS break candidates and widths](../research/ios-plan-inputs.md)).

## Consequences

- Correctness rests on the check, not on the tokenizer agreeing with TextKit, which Apple doesn't document. A disagreement costs a fallback, never wrong layout.
- Caret offsets (`CTLineGetOffsetForStringIndex`) are visual, so they give wrong widths in bidi text and zero at the end of an RTL line. Widths must come from logical-order advances.
- An inline view's width is its `NSTextAttachment.bounds` width, because Core Text gives U+FFFC no width. A soft hyphen adds the width of the `-` TextKit draws there.
