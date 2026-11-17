Type: task
Status: resolved
Blocked by: none

## Question

Scaffold the package and a minimal test app (iOS + Android, new architecture) inside this repo, rendering a set of balance test strings (varied widths, multi-line, mixed fonts, RTL, emoji) with and without a `balance` toggle. Nothing to decide: this unblocks the Android prototype. The answer records what was set up (layout, how to run each platform, tooling versions).

## Answer

Scaffolded with `create-expo-module` (Expo SDK 58, RN 0.88.1, React 19.3, TS 6) at the repo root: an Expo module (`ios/`, `android/`, `src/`, `expo-module.config.json`; package `expo.modules.textbalancer`, View feature stub) plus an Expo dev-client example app in `example/`.

- The generator's final `prepare` step failed (no `tsconfig.json`; no example `package.json`/`app.json`). Added by hand: root `tsconfig.json` (emits to `build/`), `example/{package.json,app.json,index.ts,tsconfig.json}`; removed the web `webpack.config.js`.
- Example depends on the package via `file:..`; Metro watches the parent folder and `experiments.autolinkingModuleResolution` is on. Autolinking resolves the module for Apple (verified).
- `example/App.tsx`: balance test screen (7 samples: headline, paragraph, long word, emoji, RTL, monospace) at widths 320/240/180pt with a toggle. Android currently toggles `textBreakStrategy` balanced vs highQuality; iOS shows unbalanced text.
- Verified: `npx tsc -p .` builds the package; example typechecks. **Not yet run on a simulator/emulator** (native builds not attempted).
- Run (from `example/`): `bun run ios` & `bun run android` (Metro port 8099), then `bun start`; package manager is bun.
- Nothing committed.
