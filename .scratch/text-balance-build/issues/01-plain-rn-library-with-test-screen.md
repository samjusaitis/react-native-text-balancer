# 01: Plain RN library with the test screen

Spec: [spec.md](../../text-balance/spec.md). Decisions: [ADR 0001](../../../docs/adr/0001-ios-polyfill-swizzle.md).

**What to build:** turn the repo from an Expo module scaffold into the plain, iOS-only React Native library the spec describes. Give the example app the self-checking test screen every later ticket is verified against. This is the prefactor: no balancing yet.

- Remove everything from the Expo module scaffold: the module config, the Swift and Kotlin module and view stubs, the TypeScript module, view and web files, the internal module scripts, the `android/` directory, and the Expo dependencies and scripts in the library's `package.json`. Also remove the ticket 04 prototype swizzle.
- Make the library a plain RN library:
  - a podspec at the package root and an RN CLI config with `android: null`;
  - `peerDependencies` `react-native >=0.85.0`;
  - a placeholder native source, so the pod builds;
  - no JS, no build step and no `prepare`.
- The example app stays an Expo dev-client app that depends on the library through `file:..`. It gets:
  - a `sync` script that copies the library's iOS sources, podspec and `package.json` into its `node_modules`;
  - its Metro port moved off 8099, which another local project uses.
- The example's main screen becomes the self-checking test screen:
  - Each sample renders twice at a fixed width: stock, and with `textBreakStrategy="balanced"`.
  - The screen compares their `onTextLayout` lines against the sample's expectation and shows ✅ or ❌. The expectations are: **balanced** (same line count as stock, and line widths vary less), **stock** (identical lines, for fallback cases) and **unchanged** (a plain `Text` renders identically to stock).
  - Give each sample a distinct string, for example by inserting U+2060, because RN's measure cache ignores `lineBreakStrategy`.
  - Start with a few Latin headlines (left, centred, right, RTL) and a multi-paragraph sample. Later tickets add theirs.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] No Expo module code, `android/` directory or JS source remains in the library. The package contains only `package.json`, the iOS sources, the root podspec and the RN CLI config.
- [ ] The example app installs, runs `pod install` and builds for the iOS simulator and Android emulator, with the library autolinked on iOS and not linked on Android.
- [ ] The `sync` script plus a rebuild picks up native edits in the example app.
- [ ] The test screen runs on iOS. The "unchanged" samples show ✅, and the "balanced" samples show ❌ because nothing balances yet.
- [ ] On Android, the "balanced" samples show ✅ through RN's native `balanced`.
