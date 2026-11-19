# iOS min-raggedness plan: break candidates and widths

> A design-time research note, kept as written. Numbers like 04, 08 or 10 name the prototypes listed in [the research index](README.md#prototypes). What shipped is in [the ADRs](../adr/).

Date researched: 2026-11-17. Question: how should the iOS min-raggedness plan get line-break opportunities and segment widths that match TextKit 1, so it stops falling back to stock wrapping on hyphens, CJK, Thai, bidi and inline attachments? What does that cover, what still falls back, and what does it cost against the own-component prototype's (10) 0.49ms median per build?

Builds on [ios-balancing-alternatives.md](ios-balancing-alternatives.md) (mechanism 2a, the per-line `NSTextContainer` subclass) and on the 08/10 prototype code.

Sources:
- Apple docs, fetched as doc-JSON `.md` pages (URLs inline), and the **iOS 27.2 SDK headers** in Xcode (`iPhoneOS27.2.sdk/System/Library/Frameworks/...`). Header quotes are given where a doc page has no discussion.
- RN source: the installed **0.88.1** package at `example/node_modules/react-native`. `RTLM` = `ReactCommon/react/renderer/textlayoutmanager/platform/ios/react/renderer/textlayoutmanager/RCTTextLayoutManager.mm`, `RATU` = `RCTAttributedTextUtils.mm` in the same folder.
- Prototype: `ios/BalancedParagraph.mm` on branch `prototype/10-ios-own-paragraph-component` (`BP:line`).

**Nothing here was run.** No build, no simulator. Costs are estimates scaled from prototype 10's measured numbers; every behavioural claim about TextKit that the docs don't state is marked unverified.

## Verdict

**Don't try to reproduce TextKit's breaker. Generate candidates with a Unicode line-break tokenizer, measure with additive logical-order advances, and keep TextKit as the judge: the 2a container plus the existing verify-and-fallback, plus one repair retry.** Concretely:

1. **Candidates:** `CFStringTokenizer` with `kCFStringTokenizerUnitLineBreak` over each paragraph, instead of "start of a word after a space". Then apply the paragraph's `lineBreakStrategy`: drop Hangul-internal candidates under `hangulWordPriority`. Treat both sides of U+FFFC (attachment) as candidates.
2. **Widths:** keep the one `CTLine` per paragraph that 08/10 already build, but read **per-character advances in logical order** from its runs (`CTRunGetAdvances` + `CTRunGetStringIndices`), and prefix-sum them. Segment width = `prefix[b'] - prefix[a]`, where `b'` is `b` with trailing whitespace stripped. Replace the U+FFFC advance with `NSTextAttachment.bounds.size.width`. This replaces `|x(end) - x(start)|` on visual offsets, which is wrong for bidi.
3. **DP:** unchanged cost function, but restrict each line to the window of candidates that fit in `U` (two pointers), so CJK paragraphs with a candidate per character stay cheap: O(k · m · c), with c = candidates per line, instead of O(k · m²).
4. **Impose and verify:** as in 10 (container 2a, slack, compare laid-out line starts with the plan). **New:** on a mismatch, take TextKit's actual line starts up to the first disagreement, drop the disagreeing candidate, re-plan the rest of that paragraph, and lay out once more. If it still mismatches, stock wrapping, as today.

Expected cost: about +0.05-0.15ms on the common path (no mismatch), so a median of roughly 0.55-0.65ms per build; +0.15-0.25ms (one extra layout) only on paragraphs that need the repair. Estimated, not measured.

## 1. Break-opportunity APIs on iOS

| API | On iOS? | What it gives | Verdict |
|---|---|---|---|
| `-[NSAttributedString lineBreakBeforeIndex:withinRange:]`, `lineBreakByHyphenatingBeforeIndex:withinRange:` | **No.** Doc pages list macOS 10.0+ only, and neither selector appears anywhere in the iOS 27.2 SDK's UIKit or Foundation headers (grep). | "the closest character before `index` within `aRange`, that can be placed on a new line" ([lineBreak(before:within:)](https://developer.apple.com/documentation/foundation/nsattributedstring/linebreak(before:within:).md)); the hyphenation variant returns "the character index at which the hyphen glyph should be inserted" ([lineBreakByHyphenating(before:within:)](https://developer.apple.com/documentation/foundation/nsattributedstring/linebreakbyhyphenating(before:within:).md)). | This would be the exact TextKit oracle, but it is AppKit-only. Not usable. |
| `CFStringTokenizer`, `kCFStringTokenizerUnitLineBreak` | Yes, iOS 3.0+ ([CFStringTokenizerCreate](https://developer.apple.com/documentation/corefoundation/cfstringtokenizercreate(_:_:_:_:_:).md)). | "Specifies that a string should be tokenized by line break. The `locale` parameter … is ignored." ([kCFStringTokenizerUnitLineBreak](https://developer.apple.com/documentation/corefoundation/kcfstringtokenizerunitlinebreak.md)). The class "supports languages such as Japanese and Chinese that do not delimit words by spaces" ([CFStringTokenizer](https://developer.apple.com/documentation/corefoundation/cfstringtokenizer.md)). Each token's start is a break opportunity. | **Recommended source of candidates.** Apple doesn't document which rules it implements (UAX #14? dictionary for Thai?), so agreement with TextKit is unverified and must stay guarded by the verify step. |
| `CTTypesetterSuggestLineBreak(WithOffset)` | Yes, iOS 3.2+. | "Suggests a contextual line breakpoint based on the width provided … triggered either by a hard-break character in the stream or by filling the specified width with characters" ([doc](https://developer.apple.com/documentation/coretext/cttypesettersuggestlinebreak(_:_:_:).md)). It returns only the **greedy** break for one width. | Not a candidate enumerator: to list all opportunities you'd probe width by width (one call per candidate, each one a break search). Useful only as a spot check. Core Text has no hyphenation API (no hyphen symbols in `CTTypesetter.h`/`CTLine.h`), so it can't see TextKit hyphenation either. |
| `NSLayoutManagerDelegate` `shouldBreakLineByWordBeforeCharacterAtIndex:` / `shouldBreakLineByHyphenatingBeforeCharacterAtIndex:` | Yes, iOS 7+. | Called with TextKit's **own** opportunities; returning NO means "find the next break point opportunity before `charIndex`" ([word](https://developer.apple.com/documentation/uikit/nslayoutmanagerdelegate/layoutmanager(_:shouldbreaklinebywordbeforecharacterat:).md), [hyphenating](https://developer.apple.com/documentation/uikit/nslayoutmanagerdelegate/layoutmanager(_:shouldbreaklinebyhyphenatingbeforecharacterat:).md)). | The only exact TextKit oracle on iOS, but it only reports opportunities between a line's start and its overflow point, during a layout. A "veto everything and record" pass would enumerate them in one extra layout, but what TextKit does when every opportunity is vetoed (character wrap?) is undocumented. **Option for later**, see §5. The delegate is `weak` ([NSLayoutManager.delegate](https://developer.apple.com/documentation/uikit/nslayoutmanager/delegate.md)). |
| `CFStringGetHyphenationLocationBeforeIndex` | Yes, iOS 4.2+ (`CFString.h:538`). | "Retrieve the first potential hyphenation location found before the specified location", per locale; `CFStringIsHyphenationAvailableForLocale` tests for data (`CFString.h:513-541`). | Only needed if hyphenation is ever turned on (see §3). |

Apple only says TextKit "is built on top of Core Text" ([Text Programming Guide for iOS](https://developer.apple.com/library/archive/documentation/StringsTextFonts/Conceptual/TextAndWebiPhoneOS/CustomTextProcessing/CustomTextProcessing.html)). It does not say that TextKit 1's breaker and `CFStringTokenizer`'s line-break unit share rules. That they agree on the common cases (spaces, hyphen-minus, CJK ideographs with kinsoku, Thai) is a reasonable bet, not a documented fact.

## 2. Measuring segment widths

What 08/10 do (`BP:155-166`): one `CTLine` of the paragraph, `CTLineGetOffsetForStringIndex` at each word start and at the end of the preceding word with trailing spaces stripped, width `|x(end) - x(start)|`.

Problems and fixes:

- **Bidi.** `CTLineGetOffsetForStringIndex` returns a **visual** caret position. In a mixed LTR/RTL paragraph, a logical range is not one contiguous visual interval, so `|x(end) - x(start)|` is wrong. Fix: take advances in logical order. Each `CTRun` gives glyph advances (`CTRunGetAdvances`, `CTRun.h:288`) and the string index of each glyph (`CTRunGetStringIndices`, `CTRun.h:320`). Add each glyph's advance to its character's slot, then prefix-sum by string index. TextKit breaks lines on logical ranges, and a line's width is the sum of its glyph advances whatever the visual order, so the sum is additive. (Bidi reordering after the break is TextKit's job; the plan container already positions RTL lines, `BP:110-119`.)
- **Attachments.** RN builds attachments as `NSTextAttachment` with `bounds` set to the child view's frame (`RATU:409-417`). `NSTextAttachment.bounds` is "the layout bounds of the text attachment's graphical representation in the text coordinate system" ([bounds](https://developer.apple.com/documentation/uikit/nstextattachment/bounds.md)). Core Text does not know `NSAttachmentAttributeName`; its own embedded-object mechanism is `kCTRunDelegateAttributeName`, which it recommends applying to "a range containing the single character U+FFFC" (`CTStringAttributes.h:288-303`). That is why prototype 10 saw zero width. Fix: after the prefix pass, set the U+FFFC slot to `attachment.bounds.size.width` (no need to rebuild the string with run delegates). Whether TextKit 1 adds any spacing around attachments is unverified; the slack absorbs a point or two.
- **Kerning and ligatures across a break.** In one paragraph-wide `CTLine`, the last glyph of a segment carries its kern to the next glyph, and a ligature can't span a break opportunity in practice (ligatures are within words). At a real break, that kern disappears. The error is a fraction of a point and stays inside the existing 1-4pt slack (`BP:205-208`). Letter spacing (`NSKernAttributeName`, RN `letterSpacing`) is already in the advances.
- **Trailing whitespace.** Keep stripping it from the segment end, as 08 does. Core Text treats trailing whitespace as outside the fitting width ("Creating a line for a width can result in a line that is actually longer than the desired width due to trailing whitespace", `CTLine.h:382-398`, [CTLineGetTrailingWhitespaceWidth](https://developer.apple.com/documentation/coretext/ctlinegettrailingwhitespacewidth(_:).md)). 08/10's 0 mismatches on Latin samples show TextKit 1 does the same. For CJK, U+3000 is already treated as a break space (`BP:127`).
- **Soft hyphen (U+00AD).** If TextKit breaks there it draws a hyphen glyph that isn't in the string. Add the advance of `-` in that run's font to segments ending at a SHY. Whether TextKit 1 breaks at a SHY with hyphenation off is unverified.
- **Tabs.** A tab's advance depends on its position in the line (tab stops), so widths are not additive. Skip planning for paragraphs containing `\t` (stock wrapping).
- **Exact width for the chosen lines (optional).** After the DP, `CTTypesetterCreateLine` on each of the k chosen ranges (from a `CTTypesetter` of the same paragraph) gives the exact Core Text width of each planned line, k calls instead of the O(m · c) a full exact DP would need. Only worth adding if the prototype shows slack-related mismatches.

## 3. Script and feature coverage

| Case | TextKit 1 behaviour in RN | Plan inputs after the change | Expected result |
|---|---|---|---|
| Latin, spaces | — | as today | balanced (08/10: 0 mismatches) |
| Explicit hyphens `-`, U+2010, en dash, `/` | break opportunities after them (assumed, standard UAX #14) | tokenizer candidates | balanced if the tokenizer agrees with TextKit; else repair, then stock |
| Automatic hyphenation | **Off in RN.** RN never sets `hyphenationFactor` or `usesDefaultHyphenation` (no match in RN's iOS text code). `NSLayoutManager.usesDefaultHyphenation` defaults to NO (`NSLayoutManager.h:120`), and with both hyphenation factors at 0.0 "The system disables hyphenation" ([hyphenationFactor](https://developer.apple.com/documentation/uikit/nsparagraphstyle/hyphenationfactor.md)). `NSParagraphStyle.usesDefaultHyphenation` (iOS 15+) can change that, but its default is undocumented. | none needed | n/a. If the library ever exposes hyphenation, add `CFStringGetHyphenationLocationBeforeIndex` candidates plus hyphen width. |
| Soft hyphen | unverified | tokenizer candidate plus hyphen width | balanced or stock |
| CJK (ideographs, kana, kinsoku) | break between most characters, not before closing punctuation or small kana | tokenizer candidates (one per character) and the windowed DP | balanced if the rules agree; that the tokenizer applies kinsoku the way TextKit does is unverified |
| Korean | syllable breaks by default; word-only under `NSLineBreakStrategyHangulWordPriority`, which "prohibits breaking between Hangul syllables" (`NSParagraphStyle.h:64-68`). RN maps `lineBreakStrategyIOS` to this (`RCTTextPrimitivesConversions.h:47-66`, `RATU:236-238`). | filter Hangul-internal candidates when the flag is set | balanced |
| Thai, Lao, Khmer, Burmese (dictionary-break scripts) | dictionary breaks (assumed) | tokenizer, **if** its line-break unit uses dictionaries (undocumented) | unverified: likely balanced, else repair then stock |
| Bidi-mixed paragraphs | logical breaking | logical-order advances | balanced (RTL keeps stock RN's glyph/char highlight bug from 06) |
| Inline attachments (`View` in `Text`) | width = `attachment.bounds` | U+FFFC advance = bounds width, both sides candidates | balanced (fixes 10's gap) |
| `lineBreakStrategy` `pushOut` or `standard` | "pushes out individual lines to avoid an orphan word" (`NSParagraphStyle.h:58-63`); `standard` is "the same configuration … for standard UI labels" (`:69-73`). TextKit's default is `none` ([lineBreakStrategy](https://developer.apple.com/documentation/uikit/nsparagraphstyle/linebreakstrategy-swift.property.md)); RN only sets it when the prop is given. | none | **skip planning** when `pushOut` is set (it fights the plan; untested). A balanced last line has no orphan, so plans may still verify: the verify step decides. |
| Tabs | position-dependent | — | **stock** (skipped) |
| Mixed font sizes, emoji, letter spacing | in advances | as is | balanced |

## 4. Probing TextKit instead of summing segments

- **Lay out each candidate line in TextKit:** a DP needs a width for every feasible (start, end) pair: O(m · c) of them, hundreds for a 3-line paragraph. Prototype 10's 0.49ms median covers about two full layouts plus one `CTLine`, so a layout is on the order of 0.1-0.2ms. Hundreds of probes is tens of milliseconds. **Rejected.**
- **`CTTypesetterCreateLine` per feasible pair:** exact Core Text widths without a layout manager, but still O(m · c) line objects. At an assumed 5-20µs each, that is about 1-6ms. Too costly for every build; use it only for the k chosen lines (§2).
- **Probe with `CTTypesetterSuggestLineBreak`:** greedy only (§1), so it can't produce a min-raggedness plan.
- **What the recommendation keeps from probing:** TextKit is still the judge. The verify step (`BP:288-297`) is the probe, and the repair retry adds at most one more layout on mismatching paragraphs.

## 5. Cost

Baseline (prototype 10): median 0.49ms, p90 0.88ms per stack build.

| Step | Change | Estimated delta |
|---|---|---|
| Tokenizer pass per paragraph | new | ~10-50µs for a few hundred characters |
| Logical advances from the existing `CTLine` | replaces offset lookups | ~0 to +20µs |
| Windowed DP | replaces O(k · m²) | saves time on long paragraphs; CJK with m = 300 characters and k = 4 is ~30k steps instead of ~360k |
| Repair retry | only on mismatch | +1 layout, ~0.15-0.25ms |
| Optional exact widths for k lines | optional | k × ~10µs |

**Common path: about 0.55-0.65ms median.** All figures here are estimates; the follow-up prototype must measure them.

Later option, only if the tokenizer disagrees with TextKit too often: **the delegate oracle.** One extra layout at full width with a `shouldBreakLineByWordBeforeCharacterAtIndex:` delegate that records every `charIndex` and returns NO. Each line would then report every TextKit opportunity between its start and its overflow point, which together cover the paragraph. That gives TextKit's own candidates for ~0.15-0.25ms, but it depends on undocumented behaviour when every break is vetoed, so it must be prototyped before relying on it.

## 6. What still falls back to stock wrapping

- Paragraphs containing tabs (skipped).
- `lineBreakStrategy` containing `pushOut` (skipped, or left to the verify step).
- Paragraphs where the tokenizer still disagrees with TextKit after one repair (expected rare; unknown for Thai-family scripts and kinsoku edge cases).
- Paragraphs where no k-line plan fits (one unbreakable segment wider than the box), as today.
- Truncated text (`numberOfLines` smaller than the natural line count), as today.

## 7. Unverified

- That `kCFStringTokenizerUnitLineBreak` implements UAX #14 with kinsoku and dictionary breaking for Thai/Lao/Khmer/Burmese, and that it agrees with TextKit 1's breaker. Apple documents neither.
- TextKit 1's behaviour at a soft hyphen with hyphenation off, and any extra spacing around attachments.
- The default of `NSParagraphStyle.usesDefaultHyphenation` on the paragraph styles RN creates (if YES, TextKit could hyphenate and the plan would mismatch).
- What TextKit does when the word-break delegate vetoes every opportunity (needed only for the delegate oracle).
- All cost figures.

Suggested prototype checks: one sample each for hyphenated compounds, Japanese with closing punctuation, Chinese, Korean with and without `lineBreakStrategyIOS="hangul-word"`, Thai, Arabic + English, a `View` inside `Text`, and a SHY word. Log mismatches and the repair rate, and measure the median against 0.49ms.
