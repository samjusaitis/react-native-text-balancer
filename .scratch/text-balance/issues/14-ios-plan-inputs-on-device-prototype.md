Type: prototype
Status: open
Blocked by: none
Assignee: Claude (session local_5d964b03 side session)

## Question

Do the plan inputs chosen in [11 iOS plan inputs research](11-ios-plan-inputs-research.md) hold up on a real iOS build, and with the real cost known, does the min-raggedness plan need caching? If it does, where is the cache and what is its key?

Build on the `BalancedParagraph` prototype from [10](10-ios-own-paragraph-component-prototype.md) (branch `prototype/10-ios-own-paragraph-component`). Swap its plan inputs for 11's ([research/ios-plan-inputs.md](../research/ios-plan-inputs.md)):

- break candidates from `CFStringTokenizer` `kCFStringTokenizerUnitLineBreak`;
- logical-order widths from per-glyph `CTRun` advances, with U+FFFC set to the attachment's `bounds` width, trailing whitespace stripped, and a `-` advance added after a soft hyphen;
- the DP windowed for CJK;
- one repair retry, then stock wrapping;
- paragraphs containing `\t` or a `pushOut` line-break strategy skipped.

Check, on RN 0.88.1 in the example app (Release build for timings):

1. **Agreement with TextKit:** log mismatches and repair rate for one sample each of hyphenated compounds, Japanese with closing punctuation (kinsoku), Chinese, Korean with and without `lineBreakStrategyIOS="hangul-word"`, Thai, Arabic mixed with English, a `View` inside `Text`, and a word with a soft hyphen. Note which samples fall back to stock wrapping.
2. **The open facts from 11 §7:** what TextKit 1 does at a soft hyphen with hyphenation off; any extra spacing around attachments; the default `usesDefaultHyphenation` on the paragraph styles RN builds.
3. **Cost:** median and p90 per stack build, compared with 10's 0.49ms median and 11's 0.55-0.65ms estimate. Count how often one paragraph is planned again for the same string, width and attributes across measure, draw, hit-test and `onTextLayout`.
4. **Caching:** from 3, decide whether caching is needed. If it is, choose its placement (shadow node state, the `RCTTextLayoutManager` subclass, or RN's own text layout cache), its key (string plus attributes, width, and paragraph attributes), and how it is invalidated. Prototype it if the choice isn't obvious from the numbers.

If the tokenizer disagrees too often on any script, record whether the delegate oracle (11 §5) is worth prototyping, or whether that script stays on stock wrapping.
