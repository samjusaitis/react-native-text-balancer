# Balance by minimum raggedness, not a max-width squeeze

iOS chooses each paragraph's breaks with a dynamic program that keeps default wrapping's line count and minimises Σ(U − wᵢ)², the spread of line widths, with no line wider than the box. This is what Android's native `balanced` does, so the two platforms come out line for line the same on most text. It also balances each paragraph separately, keeps a long word whole, and costs about half as much as the squeeze. The algorithm was compared side by side on branch `prototype/08-ios-min-raggedness`.

## Considered Options

- **Max-width squeeze:** binary-search the narrowest width that keeps the line count and narrow every line to it, as CSS polyfills like `react-wrap-balancer` do. It's simpler, but it leaves monospace and multi-paragraph text ragged (one width for all paragraphs), can narrow below a long word so TextKit splits it mid-word, and needs about ten layouts per build (1.26ms median against 0.59ms).
- **A user-facing choice between the two:** rejected. The prop is RN's own, and it should mean what it means on Android.
