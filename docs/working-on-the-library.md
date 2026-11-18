# Working on the library

[← Back to the README](../README.md)

The repo has an example app with a self-checking test screen, and a script that checks which React Native versions the library builds on.

## The example app

The example is an Expo app that links the library straight from the repo, so rebuilding the app picks up your native changes. It uses Bun and runs Metro on port 8100.

```bash
cd example && bun install
```

```bash
bun run ios
```

Use `bun run android` for Android.

The main screen is the test screen. It renders each sample at a fixed width three times: once with default wrapping, once balanced, and once with a different strategy (`highQuality`) to make sure the library leaves other `Text`s alone. It compares the lines each one reports through `onTextLayout`, and shows ✅ or ❌ for each check, with a summary at the top. Balanced samples pass when they keep default wrapping’s line count, move at least one break and come out more even. Fallback samples pass when they match default wrapping exactly.

On Android, the same screen checks React Native’s own `balanced`.

To check Dynamic Type, `example/scripts/sweep-text-sizes.sh` steps a booted iOS simulator through every text size while the test screen runs, and prints the result at each size. The top of the script explains how to build and install the app first.

To check that a change to the native code alters nothing it shouldn't, `example/scripts/snapshot.sh <dir>` records every balanced line (text and width) at every text size, and a screenshot of each sample on its own. Take one before the change and one after, then compare them with `diff -r`. Both runs need a Release build installed, like the sweep. To show one sample on its own, launch the app with `-only <sample id>`.

## `verify:matrix`

Before a release, or when a new React Native version or release candidate comes out, run:

```bash
bun run verify:matrix
```

For every React Native minor version from 0.85 up, plus the current release candidate, it creates a fresh app, installs the library from your latest commit as a git dependency, checks it installed only the files the library ships, runs `pod install`, and builds for the iOS simulator. Then it builds the example app for iOS and Android. At the end you get a pass/fail table.

A full run takes about 12 minutes and needs Xcode, CocoaPods and the Android SDK. You can also name the versions to test, like `bun run verify:matrix 0.86 rc`. Run `scripts/verify-matrix.sh --help` for the other options.

A full pass is what lets us release, or say a new React Native version is supported.
