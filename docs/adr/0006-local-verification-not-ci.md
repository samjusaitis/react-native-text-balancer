# Verified by local scripts and a human-read test screen, not CI

There's no CI pipeline and no UI automation. Before each release, and when a new RN minor or release candidate comes out, the maintainer runs `bun run verify:matrix` (an iOS build per RN minor from 0.85 up plus the current RC, and the example app on both platforms) and reads the example app's self-checking test screen on a simulator. A full pass gates a release and widening the supported RN range. There are no unit tests: the library has no JS, and the only behaviour worth testing is what RN's own `Text` reports through `onTextLayout`, which needs a real app.

## Consequences

Nothing stops a broken commit from landing between releases. A full matrix run takes about 12 minutes and needs Xcode, CocoaPods and the Android SDK.
