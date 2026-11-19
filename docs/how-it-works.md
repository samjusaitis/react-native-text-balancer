# How it works, and why it’s safe

[← Back to the README](../README.md)

React Native builds the text layout for every iOS `Text` in one private method, `-[RCTTextLayoutManager _textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:]`. Measuring, drawing, `onTextLayout` and tap handling all go through it.

When the app starts, the library swaps that method for its own version (this is called method swizzling). The new version calls React Native’s original first. Then, only if the `Text` asked for `textBreakStrategy="balanced"`, it lays the text out the way React Native built it, chooses balanced breaks for each paragraph from those lines (keeping the same number of lines), tells iOS to lay the lines out that way, and checks that they came out as planned. If they didn’t, that paragraph goes back to default wrapping. Text that truncates at `numberOfLines`, or is cut off by a fixed height, keeps default wrapping. Every other `Text` gets exactly what React Native built.

Because everything goes through that one method, the text you measure, the text you see and the text you tap on always agree.

## Why a private method?

iOS has no built-in way to balance text, and React Native doesn’t give libraries a public way to change how `Text` lays out. The other options were all worse:

- **Shipping our own `Text` component** would mean a wrapper you’d have to use instead of React Native’s, which would always be playing catch-up with it.
- **Patching React Native itself** doesn’t work anymore, because React Native now ships its core prebuilt, so a patch never gets compiled.

## What if React Native changes that method?

The library checks before it swaps anything. If the class or the method is missing, or the method’s signature isn’t exactly what it expects, it leaves React Native alone. Your app keeps running with default wrapping, and in development you get one warning in the console:

```
react-native-text-balancer: ... textBreakStrategy="balanced" uses default wrapping on iOS with this React Native version.
```

So a React Native upgrade can turn balancing off, but it can’t crash your app. The method’s signature hasn’t changed from React Native 0.85 up to its current main branch.

## React Native bugs you might notice

These come from React Native itself and happen with or without the library:

- **Right-to-left press highlights land in the wrong place on iOS.** When you press a span in Arabic or other right-to-left text, React Native draws the highlight over the wrong part of the text, because it passes a character range where a glyph range is expected. Taps still go to the right span.
- **Android ignores a runtime switch to `balanced`.** If you change `textBreakStrategy` while the app is running, say from `"highQuality"` to `"balanced"`, Android doesn’t always pick up the change. The text keeps its old wrapping until the `Text` is re-created. You can force that by giving it a `key` that changes along with the strategy.

## Is it fast?

Yes. In a Release build, balancing a `Text` usually takes about a third of a millisecond, and the slowest cases (Korean and Arabic) take about a millisecond. Balancing lays the text out twice: once as React Native built it, to plan the breaks, and once with the balanced breaks. Text that keeps default wrapping (it fits on one line, truncates, or can’t balance) is laid out once, and that’s the layout React Native then uses, so it costs no more than React Native on its own. The library also remembers the breaks it chose for each string and width, so when React Native lays out the same text again, which it does a lot when drawing, reusing those breaks costs almost nothing. It doesn’t remember anything for text cut off by a fixed height, because the result there depends on the height: if the box grows, the text balances at its new size.

## Android

On Android this library does nothing. React Native already balances there on its own.

## Why it’s built this way

The [architecture decision records](adr/) explain the main choices, such as minimum raggedness over a simpler squeeze, and why there’s no Android code. The [research and prototypes](research/README.md) behind them are kept too.
