# react-native-text-balancer

A drop-in React Native `Text` whose `balance` prop evens out line lengths, like CSS `text-wrap: balance`.

## Language

**Balance**:
Line breaks chosen to minimise raggedness, so a paragraph's lines are as close to the same length as possible without adding lines.
_Avoid_: Even wrapping, squeeze, Knuth-Plass

**Stock wrapping**:
Line breaks exactly as React Native's own `Text` would lay them out.
_Avoid_: Default layout, unbalanced layout

**Fallback**:
A paragraph that `balance` can't balance and therefore renders with stock wrapping, without any error.
_Avoid_: Failure, degradation

**Outermost Text**:
The `Text` that isn't nested inside another `Text`; the only one where `balance` applies.
_Avoid_: Root span, parent text
