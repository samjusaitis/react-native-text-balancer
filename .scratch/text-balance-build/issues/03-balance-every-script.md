# 03: Balance every script

Spec: [spec.md](../../text-balance/spec.md) (Choosing balanced breaks for one paragraph). Detail: tickets 11 and 14 in [the map](../../text-balance/map.md); the closest implementation is on branch `prototype/14-ios-plan-inputs-on-device`.

**What to build:** balanced text on iOS works beyond space-separated Latin text: CJK, Korean, Thai, bidi, inline views, and explicit and soft hyphens.

- Break points come from `CFStringTokenizer` line-break units, which follow UAX #14, including kinsoku and dictionary breaking for Thai.
- Widths come from logical-order `CTRun` glyph advances, prefix-summed by string index. Inline attachments (U+FFFC) take their `bounds` width. Trailing whitespace is stripped from each segment, and the advance of `-` is added after a soft hyphen.
- The DP is windowed for long CJK paragraphs.
- On a mismatch, run one repair retry before falling back to stock wrapping.

**Blocked by:** 02.

**Status:** done

- [x] New test-screen samples show ✅ "balanced" on iOS: hyphenated compounds, a soft-hyphen word, Japanese with closing punctuation, Chinese, Korean in default and `hangul-word` modes, Thai, Arabic mixed with English, and a `View` inside `Text`.
- [x] No Japanese balanced line starts with closing punctuation or small kana.
- [x] Every ticket 02 sample still passes.
- [x] A Release build stays within the spec's budget: a median of about 0.5ms and a p90 of about 1.4ms per uncached build.

## Comments

- **Implementation:** `ios/RNTBBalancer.mm`. Candidates from `CFStringTokenizer` line-break units plus both sides of U+FFFC, with Hangul-internal breaks dropped under hangul-word priority. Widths from logical-order `CTRun` advances, attachment `bounds` width for U+FFFC, trailing whitespace stripped, the `-` advance added at a soft hyphen. Windowed DP (scans line starts leftwards only while the line fits). On a mismatch, one repair retry (drop the chosen break, take TextKit's, choose again), then stock wrapping for that paragraph.
- **Test screen:** simulator, RN 0.88.1, Debug and Release: 32/32. New samples: hyphenated compounds, soft-hyphen word, Japanese (with a kinsoku check on the balanced lines), Chinese, Korean default and `hangul-word`, Thai, Arabic mixed with English, `View` inside `Text` (`inlineView` on a sample). The soft-hyphen, `hangul-word` and inline-view texts are ones that wrap raggedly under stock wrapping; the ticket 14 texts were already even at 240pt.
- **Repair checked by forcing it:** with a bogus mid-segment candidate added per segment (temporary code), 40 repairs fired. Paragraphs either held after the retry or fell back to exactly stock; every "unchanged" twin stayed ✅.
- **Timing (Release, iOS 27.2 simulator, time inside the balancer per build, 6 launches, n=294):** median 0.35ms, p90 0.90ms, mean 0.49ms. Korean and Arabic are the slowest at about 0.9ms.
- **Fewer layouts:** every change to a text container's geometry makes TextKit lay the whole storage out again. Ticket 02 moved RN's container to the counting geometry and back, which cost two extra layouts (median 0.56ms, p90 1.79ms before). The stock count now runs in the width container itself, which changes geometry once, and RN's container is never touched, so falling back is just putting it back.
- **Bug found and fixed on the way:** in measure, RN's height is already unbounded, so setting the width container to RN's geometry changed nothing and TextKit kept the stale stock layout. The first check then "repaired" to different breaks than draw used, and the inline `View` was placed from measure's layout, over the wrong word. The layout is now invalidated explicitly after the line widths are filled in.
- **Not done here:** tabs and `push-out` (ticket 04), the break cache (ticket 05).

