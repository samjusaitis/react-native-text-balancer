# react-native-text-balancer

An iOS polyfill that makes React Native's `textBreakStrategy="balanced"` even out line lengths on iOS as it does on Android, like CSS `text-wrap: balance`.

## Language

**Balance**:
Line breaks chosen to minimise raggedness, so a paragraph's lines are as close to the same length as possible without adding lines.
_Avoid_: Even wrapping, squeeze, Knuth-Plass

**Stock wrapping**:
Line breaks exactly as React Native's own `Text` would lay them out.
_Avoid_: Default layout, unbalanced layout

**Fallback**:
A paragraph set to `textBreakStrategy="balanced"` that iOS can't balance, so it renders with stock wrapping and no error.
_Avoid_: Failure, degradation

**Outermost Text**:
The `Text` that isn't nested inside another `Text`. It's the only one whose `textBreakStrategy` React Native reads, so it's the only one that can balance.
_Avoid_: Root span, parent text
