# React Native Text Balancer

React Native’s `Text` component has a `textBreakStrategy="balanced"` prop to
wrap text lines in such a way that best balances the number of characters on
each line. However, the prop is only functional on Android. This library makes
it work on iOS too.

Install it, rebuild your iOS app, and `textBreakStrategy="balanced"` balances on both platforms, much like CSS `text-wrap: balance` on the web.

```tsx
<Text textBreakStrategy="balanced">
  Balanced text wrapping keeps written headlines tidy on every device
</Text>
```

```
 DEFAULT WRAPPING                     BALANCED
┌────────────────────────────────┐   ┌────────────────────────────────┐
│Balanced text wrapping keeps    │   │Balanced text wrapping          │
│written headlines tidy on every │   │keeps written headlines         │
│device                          │   │tidy on every device            │
└────────────────────────────────┘   └────────────────────────────────┘
```

## Requirements

- React Native 0.85 or newer
- The New Architecture
- An Expo app using a [development
  build](https://docs.expo.dev/develop/development-builds/introduction/), or a bare React Native app

## Install

Install straight from GitHub, pinned to a release tag:

```bash
bun add github:samjusaitis/react-native-text-balancer#v0.1.0
```

Or with npm:

```bash
npm install github:samjusaitis/react-native-text-balancer#v0.1.0
```

> [!NOTE]
> If you’re on a React Native release candidate, npm will refuse the install. Add `--legacy-peer-deps` to get past it.

Then rebuild your iOS app. The library links itself automatically, so there’s nothing else to set up, and no Expo config plugin to add.

## Learn more

- **[What it does](docs/what-it-does.md)** — what balances, what falls back to default wrapping, and what might surprise you.
- **[How it works, and why it’s safe](docs/how-it-works.md)** – the private method it swizzles, how it fails safe, speed, and a note on Android.
- **[Working on the library](docs/working-on-the-library.md)** – the example app’s test screen and `verify:matrix`.

## Future improvements

- **Balance justified text on iOS.** On Android, `textAlign: 'justify'` with `textBreakStrategy="balanced"` balances the breaks and then justifies each line to the full width. On iOS, justified paragraphs currently keep default wrapping, because the library balances by narrowing lines and iOS would then justify each line only to its narrowed width. Matching Android means forcing the balanced breaks at full width instead. See [what it does](docs/what-it-does.md#things-that-might-surprise-you).

## License

MIT
