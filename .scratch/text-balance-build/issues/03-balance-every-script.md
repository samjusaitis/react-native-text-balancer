# 03: Balance every script

Spec: [spec.md](../../text-balance/spec.md) (Planning one paragraph). Detail: tickets 11 and 14 in [the map](../../text-balance/map.md); the closest implementation is on branch `prototype/14-ios-plan-inputs-on-device`.

**What to build:** balanced text on iOS works beyond space-separated Latin text: CJK, Korean, Thai, bidi, inline views, and explicit and soft hyphens.

- Break points come from `CFStringTokenizer` line-break units, which follow UAX #14, including kinsoku and dictionary breaking for Thai.
- Widths come from logical-order `CTRun` glyph advances, prefix-summed by string index. Inline attachments (U+FFFC) take their `bounds` width. Trailing whitespace is stripped from each segment, and the advance of `-` is added after a soft hyphen.
- The DP is windowed for long CJK paragraphs.
- On a mismatch, run one repair retry before falling back to stock wrapping.

**Blocked by:** 02.

**Status:** ready-for-agent

- [ ] New test-screen samples show ✅ "balanced" on iOS: hyphenated compounds, a soft-hyphen word, Japanese with closing punctuation, Chinese, Korean in default and `hangul-word` modes, Thai, Arabic mixed with English, and a `View` inside `Text`.
- [ ] No Japanese balanced line starts with closing punctuation or small kana.
- [ ] Every ticket 02 sample still passes.
- [ ] A Release build stays within the spec's budget: a median of about 0.5ms and a p90 of about 1.4ms per uncached build.
