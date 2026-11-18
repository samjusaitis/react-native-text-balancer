# 07: README

Spec: [spec.md](../../text-balance/spec.md) (Solution; Further Notes). Terms: [GLOSSARY.md](../../../GLOSSARY.md).

**What to build:** a README that lets anyone who finds the public repo understand, install and use the library without the original context.

- What it does: makes RN's `textBreakStrategy="balanced"` balance on iOS, as on Android, like CSS `text-wrap: balance`.
- Install as a git dependency pinned to a tag, then rebuild iOS. It works in bare RN and Expo dev builds, with no config plugin.
- Usage: the one prop. Only the outermost `Text` is read.
- Supported versions: RN ≥ 0.85, New Architecture only. There's no Expo Go support.
- What balances (Latin, CJK, Korean, Thai, bidi, inline views, hyphens and soft
  hyphens, `adjustsFontSizeToFit`, `numberOfLines` that fits) and what falls
  back to default wrapping (tabs, an over-wide word, truncating text; Thai-family
  and kinsoku edge cases may fall back).
- The orphan caveat, the `push-out` behaviour, and that a third-party `Text` setting `balanced` will balance too.
- The box keeps the default width: a wrapped `Text` without a fixed width takes the full available width, as in RN without the library and CSS. It doesn't shrink to the widest balanced line.
- On Android, switching `textBreakStrategy` at runtime needs a `key` change to re-apply.
- Why it swizzles a private RN method, how the guard fails safe, and how to run the example app and `verify:matrix`.

**Blocked by:** 03, 04, 05.

**Status:** done (one criterion waits on the first tag)

- [ ] A reader new to the repo can install the library in a fresh RN 0.85+ app from the README alone and see balanced text on iOS.
- [x] Every balances/falls-back claim matches a test-screen sample result.
- [x] It uses the glossary's terms (balance, default wrapping, outermost Text).

## Comments

- **Implementation:** `README.md`, written for someone who finds the repo cold: what it does, requirements, install, usage, what balances and what falls back, the surprises (orphans, box width, `push-out`, third-party `Text`, iOS/Android differences), the Android `key` workaround, how the swizzle and guard work, speed, and the example app and `verify:matrix`.
- **Claims checked against the test screen:** the "What balances" list is exactly the `balanced` samples in `example/samples.ts` (plus the Dynamic Type samples for rebalancing). The fallback list is the `default` samples: tab, word wider than the box, and `numberOfLines` that truncates. The Thai-family and kinsoku line is worded as "may", from the spec's known limits, since no sample shows those falling back. The spec's monospace headline isn't a sample, so it isn't claimed. Speed numbers are ticket 03's Release measurements.
- **Install notes from ticket 06:** install commands for bun and npm, and `--legacy-peer-deps` for RN release candidates. Bun's git install ignores `files` and copies every tracked file, but that's about 490 KB, so the README doesn't mention it.
- **Not done:** the install from the README alone hasn't been tried end to end, because `v0.1.0` isn't tagged or pushed yet. `verify:matrix` already covers the same npm git install from a local commit on every supported RN minor.
