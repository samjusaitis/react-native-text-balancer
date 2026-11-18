# 06: verify:matrix

Spec: [spec.md](../../text-balance/spec.md) (Testing Decisions). Detail: ticket 13 in [the map](../../text-balance/map.md).

**What to build:** one local command tells the maintainer which RN versions the library builds on, before a release or when a new RN minor or RC appears.

- For each RN minor from 0.85 up, plus the current RC: create a fresh bare RN app, install the library, run `pod install` and run a Debug iOS simulator build.
- Also build the Expo example app for iOS and Android.
- Print a pass/fail table. A full pass gates a release and widening the documented RN range.

**Blocked by:** 02.

**Status:** done

- [x] One command runs the whole matrix unattended and prints a pass/fail table per RN version, plus the example builds.
- [x] The current code passes on every RN minor from 0.85 to the latest, and on the RC.
- [x] The bare apps install the library from a git URL (a local tag or commit), and the installed package holds only the shipped files (`package.json`, iOS sources, podspec, RN CLI config). This confirms the `files` allowlist applies to git installs, which bun's `file:` install ignored (ticket 01).
- [x] Pointing it at RN 0.84 fails with the library's `#error`, not an obscure compile error.

## Comments

- **Implementation:** `scripts/verify-matrix.sh`, run as `bun run verify:matrix`.
  - With no arguments, it reads npm for every RN minor from 0.85 up (the latest patch of each), plus the `next` RC when it's newer. Then it builds the Expo example.
  - Arguments pick the versions instead (`0.84`, `0.85.2`, `rc`).
  - `--ref` picks the commit the bare apps install. It defaults to `HEAD`, and the script warns when there are uncommitted library changes, which the bare apps don't see.
  - The example builds from the working tree.
  - `--no-example`, `--keep` and `--list` do what they say.
  - Logs go to `$TMPDIR/rntb-verify-matrix/logs`, one section per step, and each bare app is deleted after its row.
- **Per RN version**, in order:
  1. `@react-native-community/cli init --version X`.
  2. `npm install --legacy-peer-deps react-native-text-balancer@git+file://<repo>#<commit>`.
  3. A check that the installed files exactly match what the commit's `files` allowlist ships, plus the `package.json` and `README.md` npm always adds.
  4. `pod install`. This step fails unless `Podfile.lock` lists `ReactNativeTextBalancer`.
  5. A Debug `xcodebuild` for the generic iOS simulator.

  A failed row's note comes from the failed step's log section: the library's `#error` if it's there, otherwise the first error line.
- **Peer range and RCs:** `>=0.85.0` doesn't match prereleases, so npm refuses `0.89.0-rc.2` (and 0.84) with ERESOLVE. An app on the RC hits the same error. The bare apps install with `--legacy-peer-deps` so the build decides, and a PEER column (`in`/`out`) shows the gap without failing the row. No fixed range admits future RCs. npm matches peer ranges without prereleases, and `>=0.85.0-0` only admits 0.85.0's own prereleases (checked with `semver -r`). The only option is an `|| >=0.89.0-0` clause, rewritten for each RC. So the range stays, and RC users install with `--legacy-peer-deps`, which the README (07) should say.
- **Package contents:** a git install through npm packs the repo, so the `files` allowlist applies. The check covers npm only. A bun git install (`bun add git+file://…#<commit>`) ignores `files`, like bun's `file:` install in ticket 01: it copies all 53 tracked files, `.scratch/` included. Only tracked files are copied, so there are no example builds, and the build is unaffected. Ticket 07 (README) should say this, or recommend npm or yarn for installing.
- **Prebuilt core:** the bare-app templates use React Native's prebuilt core by default, and both library sources compile against its headers. The Expo example builds RN from source, so both setups are covered on 0.88. `RCT_USE_PREBUILT_RNCORE=0` builds the bare apps from source too.
- **Run (2026-11-18, Xcode 27.2, library at `efab3ad`):** every row passes: RN 0.85.3, 0.86.3, 0.87.1 and 0.88.1 (PEER `in`), 0.89.0-rc.2 (PEER `out`), and the example on iOS and Android. The whole run takes about 12 minutes. `bun run verify:matrix 0.84` fails at the build step, and its only compile error is `RNTextBalancer.mm:32: error: "react-native-text-balancer needs React Native 0.85 or newer (New Architecture)."`
