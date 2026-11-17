Type: prototype
Status: open
Blocked by: 05

## Question

Does swapping the 04 spike's negative `tailIndent` for `NSTextContainer.exclusionPaths`, applied after RN's `scaleFontSizeToFitSize:`, remove both trade-offs from [04 iOS tailIndent injection prototype](04-ios-tailindent-injection-prototype.md) while keeping measure, draw, hit-test and `onTextLayout` in agreement? Specifically:

1. The pressed nested-span highlight (including a span that wraps across lines) stops at the balanced edge, not the box edge.
2. `adjustsFontSizeToFit` text balances after scaling and still fits; `numberOfLines` truncation is skipped or capped.
3. Centred, right-aligned and RTL text keep correct alignment (strip on the trailing side, or half on each side for centred).

Also record exclusion-path layout cost against the ~1ms `tailIndent` baseline, and note any interaction with the `enableIOSCompressedTextFrameAdjustment` path. Start from `ios/PrototypeBalanceSwizzle.mm`; approach and line refs in [research/ios-balancing-alternatives.md](../research/ios-balancing-alternatives.md).
