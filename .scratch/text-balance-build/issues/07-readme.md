# 07: README

Spec: [spec.md](../../text-balance/spec.md) (Solution; Further Notes). Terms: [GLOSSARY.md](../../../GLOSSARY.md).

**What to build:** a README that lets anyone who finds the public repo understand, install and use the library without the original context.

- What it does: makes RN's `textBreakStrategy="balanced"` balance on iOS, as on Android, like CSS `text-wrap: balance`.
- Install as a git dependency pinned to a tag, then rebuild iOS. It works in bare RN and Expo dev builds, with no config plugin.
- Usage: the one prop. Only the outermost `Text` is read.
- Supported versions: RN ≥ 0.85, New Architecture only. There's no Expo Go support.
- What balances (Latin, CJK, Korean, Thai, bidi, inline views, hyphens and soft
  hyphens, `adjustsFontSizeToFit`, `numberOfLines` that fits) and what falls
  back to stock wrapping (tabs, an over-wide word, truncating text; Thai-family
  and kinsoku edge cases may fall back).
- The orphan caveat, the `push-out` behaviour, and that a third-party `Text` setting `balanced` will balance too.
- On Android, switching `textBreakStrategy` at runtime needs a `key` change to re-apply.
- Why it swizzles a private RN method, how the guard fails safe, and how to run the example app and `verify:matrix`.

**Blocked by:** 03, 04, 05.

**Status:** ready-for-agent

- [ ] A reader new to the repo can install the library in a fresh RN 0.85+ app from the README alone and see balanced text on iOS.
- [ ] Every balances/falls-back claim matches a test-screen sample result.
- [ ] It uses the glossary's terms (balance, stock wrapping, outermost Text).
