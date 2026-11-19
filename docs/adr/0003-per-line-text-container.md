# Impose balanced breaks with a per-line `NSTextContainer`, after RN's font scaling

The hook calls RN's original builder first, so `adjustsFontSizeToFit` has already scaled the text, and then swaps in an `NSTextContainer` subclass whose `lineFragmentRectForProposedRect:atIndex:…` returns each balanced line's width, keyed by the line's start index. The container itself, and so the `Text` box, keeps its default size. Each line fragment hugs its text, so a pressed span's highlight follows the balanced lines.

## Considered Options

- **Negative `NSParagraphStyle.tailIndent`:** it worked for measure, draw, hit-test and `onTextLayout`, but line fragments stayed full width, so a pressed span's highlight ran past the narrowed line to the box edge. It also had to be applied before RN's font scaling, so `adjustsFontSizeToFit` couldn't balance.
- **`NSTextContainer.exclusionPaths` strip:** fixed both problems (branch `prototype/06-ios-exclusion-paths`), but a strip narrows every line by the same amount, so it can only do a max-width squeeze ([ADR 0002](0002-minimum-raggedness.md)).
- **`shouldBreakLineByWordBeforeCharacterAtIndex:` delegate veto:** can stop TextKit breaking where the plan doesn't, but can't set line widths on its own. It wasn't needed once the container returns per-line widths.
