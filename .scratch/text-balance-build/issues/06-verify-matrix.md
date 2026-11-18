# 06: verify:matrix

Spec: [spec.md](../../text-balance/spec.md) (Testing Decisions). Detail: ticket 13 in [the map](../../text-balance/map.md).

**What to build:** one local command tells the maintainer which RN versions the library builds on, before a release or when a new RN minor or RC appears.

- For each RN minor from 0.85 up, plus the current RC: create a fresh bare RN app, install the library, run `pod install` and run a Debug iOS simulator build.
- Also build the Expo example app for iOS and Android.
- Print a pass/fail table. A full pass gates a release and widening the documented RN range.

**Blocked by:** 02.

**Status:** ready-for-agent

- [ ] One command runs the whole matrix unattended and prints a pass/fail table per RN version, plus the example builds.
- [ ] The current code passes on every RN minor from 0.85 to the latest, and on the RC.
- [ ] Pointing it at RN 0.84 fails with the library's `#error`, not an obscure compile error.
