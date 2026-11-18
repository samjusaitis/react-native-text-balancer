# React Native Text Balancer

An iOS polyfill that makes React Native's `textBreakStrategy="balanced"` even out line lengths on iOS as it does on Android, like CSS `text-wrap: balance`.

## Language

**Balance**:
Line breaks chosen to minimise raggedness, so a paragraph's lines are as close to the same length as possible without adding lines.
_Avoid_: Even wrapping, squeeze, Knuth-Plass

**Balanced breaks**:
The line breaks the library chooses for one paragraph so it **balances**: where each line starts, and so how wide each line is. They're chosen from the paragraph's break candidates (every place a line could break), imposed on TextKit, then checked. A paragraph whose balanced breaks don't fit or don't hold keeps **default wrapping**.
_Avoid_: Plan, layout

**Default wrapping**:
Exactly what React Native's own `Text` does without the library: its own line breaks and layout. It means "without the library", not a prop's default value (on Android, `textBreakStrategy` defaults to `highQuality`).
_Avoid_: Stock wrapping, unbalanced layout

**Outermost Text**:
The `Text` that isn't nested inside another `Text`. It's the only one whose `textBreakStrategy` React Native reads, so it's the only one that can balance.
_Avoid_: Root span, parent text
