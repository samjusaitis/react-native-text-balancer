Type: grilling
Status: resolved
Assignee: Sam Jusaitis (claimed)
Blocked by: none

## Question

How is the library packaged and verified? Decide for the spec:

- **Scaffold:** keep the Expo module (`create-expo-module`) plus the codegen component wired by `react-native.config.js` and a root podspec (10), or move to `create-react-native-library`. Do bare RN apps work without Expo, and does Expo need a config plugin at all?
- **Android side:** is it pure JS (native `textBreakStrategy` + `key` remount), so the Android native module stub can be dropped?
- **Example app:** link vs. bun copy of `file:..` (native edits currently need an rsync).
- **CI:** the per-SDK matrix from 09 (RN ≥ 0.85): which RN/Expo versions, which platforms, and what's checked (build, a screenshot test of balanced vs. stock, the dev warning when the selector is missing).
- **Publishing:** what goes into the npm package (`.npmignore`, built `build/`, podspec location).

## Grilling notes (Sam)

- Round 1: dropping Expo and the Android stub accepted. A bun workspace for the example was rejected as too much complexity for the gain (the copy only costs an rsync per edit).
- Round 2: checks run on a local machine, not in a CI pipeline. Jest isn't wanted. Any runner is fine if it's better, but only Jest can realistically render RN components, and a pure dispatch function makes rendering unnecessary, so `bun test` stays.

## Answer

**The package is a plain React Native library, not an Expo module, and it's verified by local scripts, not CI.** Sam's decisions, 2026-11-17.

- **Scaffold:**
  - Delete `expo-module.config.json`, the Swift/Kotlin `Module` and `View` stubs, `ReactNativeTextBalancerView*`, the `.web.ts` files, `internal/module_scripts`, and the `expo` peer and dev dependencies. None of the library uses the Expo Modules API.
  - What ships natively: the codegen component `BalancedParagraph` (`codegenConfig` in `package.json`, as in [10](10-ios-own-paragraph-component-prototype.md)), `ReactNativeTextBalancer.podspec` at the package root, and `react-native.config.js` with `dependency.platforms: { ios: {}, android: null }`.
  - Bare RN apps autolink it through the RN CLI. Expo apps (dev builds) autolink it through prebuild like any RN community package. There's no config plugin, because there's nothing to configure.
- **Android:** pure JS (native `textBreakStrategy="balanced"` plus the `key` remount from [07](07-android-text-break-strategy-rerender-research.md)). There's no `android/` directory and no Gradle module.
- **Build:** `react-native-builder-bob` with the `module` target (`lib/module`) and the `typescript` target (`lib/typescript`). `package.json` gets `main`, `types`, `exports` and `source: src`.
- **`peerDependencies`:** `react-native: ">=0.85.0"` and `react: "*"`, with no upper bound and no `expo`. The native code has an `#error` below RN 0.85 (version macros in `<cxxreact/ReactNativeVersion.h>`; `main` reports 1000.0).
- **npm contents:** a `files` allowlist (`src/`, `lib/`, `ios/`, `ReactNativeTextBalancer.podspec`, `react-native.config.js`) replaces `.npmignore`. `src/` ships because codegen reads the spec from it. The root `build/` folder goes.
- **Example app:** stays an Expo dev-client app depending on `"file:.."` (a copy). A `bun run sync` script in `example/` rsyncs `src/`, `ios/`, the podspec and `package.json` into `example/node_modules/react-native-text-balancer`. The README documents the loop: sync after edits, then a native rebuild after iOS edits. No workspace.
- **Verification (local, no CI pipeline):**
  - The wrapper's logic is a pure function, `resolveText(props, platform)`. It returns the host to render (RN `Text` or `BalancedParagraph`), the host and inner-`Text` props, the `key`, and the dev warnings to emit. `Text.tsx` is a thin shell around it.
  - `bun run check` runs on every change: `bun test` over `resolveText` (no RN import, no renderer), `tsc` and `eslint`. The tests cover the Android strategy and `key`, the iOS host wrapping and the root-only props moved onto the host, `textBreakStrategy` stripping, the `lineBreakStrategyIOS` mapping, nested `balance` ignored, and the warnings.
  - `bun run verify:matrix` runs before each release and whenever a new RN minor or RC appears. It builds a fresh bare RN app (`@react-native-community/cli init --version X`) for each RN minor from 0.85 up plus the current RC, installs the package, runs `pod install` and a Debug simulator build. It also builds the Expo example for iOS and Android. It prints a pass/fail table. A full pass gates a release and widening the tested range. The matrix is per RN minor, not per Expo SDK (0.87 has no SDK).
  - The example app has a self-checking test screen. It renders the samples stock and balanced, compares the `onTextLayout` lines, and shows ✅ or ❌ per sample. A human reads it on the iOS simulator and an Android emulator during the pre-release run, and checks the missing-selector warning and Android behaviour by eye. There's no UI automation.
- **Out of the spec:** versioning, changelog and the publishing workflow are left to the implementer.

[09](09-ios-hook-delivery-grilling.md) and [ADR 0001](../../../docs/adr/0001-ios-polyfill-swizzle.md) now name the local `verify:matrix` run where they said CI.
