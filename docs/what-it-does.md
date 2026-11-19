# What it does

[← Back to the README](../README.md)

When a `Text` is set to balance, the library keeps the same number of lines default wrapping would give, and moves the line breaks so the lines come out as close to the same length as it can. The text never gets taller, and the box around it doesn’t change size, so nothing else in the layout moves.

Some things to know:

- **Each paragraph balances on its own.** If your text has line breaks (`\n`, or a line separator `\u2028`) in it, each part gets balanced separately, so a short paragraph isn’t left ragged because of a long one.
- **Alignment stays put.** Left, centred, right-aligned and right-to-left text keep their edges.
- **`adjustsFontSizeToFit` works.** React Native shrinks the font first, then the library balances the shrunk text.
- **`numberOfLines` works when the text fits.** If the text fits within `numberOfLines`, it balances across that many lines. If it doesn’t fit and gets cut off with an ellipsis, it keeps default wrapping, so the ellipsis lands exactly where it would without the library.
- **Text size changes rebalance.** When someone changes their text size in iOS Settings (Dynamic Type), balanced text rebalances at the new size.
- **Everything else on `Text` keeps working.** Nested spans with `onPress` still register taps and their press highlight follows the balanced lines. `selectable` works. `onTextLayout` reports the balanced lines, so it matches what’s on screen.

## What balances

The example app’s test screen checks all of these on every run:

- Latin text: left-aligned, centred, right-aligned and right-to-left
- Several paragraphs in one `Text`, and parts split by a line separator (`\u2028`)
- Hyphenated words (like "state-of-the-art") and soft hyphens (`\u00AD`)
- Japanese, keeping its line-start rules (no line starts with closing punctuation or small kana)
- Chinese
- Korean, both by default and with `lineBreakStrategyIOS="hangul-word"`
- Thai
- Arabic mixed with English
- A `View` inside a `Text`, like an icon or a badge
- Nested pressable spans, in a `selectable` `Text`
- `adjustsFontSizeToFit`
- `numberOfLines`, when the text fits
- A `Text` with no fixed width
- `lineBreakStrategyIOS="push-out"` (see below)

## What falls back to default wrapping

Sometimes the library can’t balance a paragraph. When that happens, the paragraph gets default wrapping, the same as if you hadn’t asked for balance. It never shows an error, and it’s never worse than not having the library. These cases fall back:

- **A paragraph with a tab in it.** Where a tab stop lands depends on where the tab falls on its line, so the library can’t work out line widths ahead of time.
- **A justified paragraph (`textAlign: 'justify'`).** The library balances by making lines narrower, and iOS would then justify each line only to its narrower width, losing the straight right edge. So justified text keeps default wrapping and stays justified. This differs from Android, which balances justified text and then stretches each line to the full width (see below).
- **A word wider than the box.** If one word can’t fit on a line at all, there’s no way to balance around it.
- **Text that gets cut off by `numberOfLines`.** See above.
- **Text that gets cut off by a fixed height.** If the box is too short for the text, the lines that do show keep default wrapping. When the box later grows tall enough, the text balances.

Thai, and other scripts that break lines the way Thai does, as well as some tricky Japanese line-start cases, may also occasionally fall back. Fallback happens one paragraph at a time, so the other paragraphs in the same `Text` still balance.

## Things that might surprise you

**You can still get a lonely last word.** Balancing usually fixes this, but it can’t always. If a paragraph falls back to default wrapping, or if the only places the text can break leave one word on its own, you’ll still see it.

**The box doesn’t shrink to fit the balanced lines.** A `Text` without a fixed width takes up all the width it’s given, just as it does without the library, and as CSS does. Balancing makes the lines inside it shorter, but the box stays the same width, so a view sitting beside the text won’t move closer to it.

**`lineBreakStrategyIOS` is left alone.** The library doesn’t change your text’s styles, including `lineBreakStrategyIOS="push-out"`, which tries to avoid a short last line in its own way. React Native’s iOS text currently ignores `push-out`, so it has no effect on balanced paragraphs or any others.

**Other libraries’ `Text` balances too.** If a third-party component already sets `textBreakStrategy="balanced"` (for Android), it starts balancing on iOS as soon as you install this library. That’s on purpose: the prop now means the same thing on both platforms.

**Lines may not break in the same places on iOS and Android.** The two platforms use different fonts and text engines, so the balanced breaks can differ a little.

**Justified text balances on Android but not on iOS.** On Android, `textAlign: 'justify'` with `textBreakStrategy="balanced"` gets balanced breaks and each line but the last stretched to the full width, which can leave wide gaps between words on a shortened line. On iOS, justified paragraphs keep default wrapping. This is a known difference, listed as a future improvement in the [README](../README.md#future-improvements).
