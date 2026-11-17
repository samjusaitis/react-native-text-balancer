Type: research
Status: resolved
Assignee: Sam Jusaitis (claimed, research subagent)
Blocked by: none

## Question

How should the iOS min-raggedness plan get **break opportunities and widths that match TextKit exactly**, so that it doesn't fall back to stock wrapping on real-world text? The 08/10 spikes split only on spaces and measure words with one `CTLine`; this misses hyphens and soft hyphens, CJK (break between most ideographs, kinsoku rules), Thai and other dictionary-break scripts, bidi-mixed paragraphs, and inline attachments (the attachment character gets zero width). Survey:

- Apple APIs for line-break opportunities that agree with TextKit 1 / Core Text: `CFStringTokenizer` (`kCFStringTokenizerUnitLineBreak`), `-[NSAttributedString lineBreakBeforeIndex:withinRange:]` / `lineBreakByHyphenatingBeforeIndex:`, `CTTypesetterSuggestLineBreak` probing, and `NSLayoutManager` delegate break callbacks.
- How to measure segment widths consistently with layout (kerning and ligatures across break points, trailing whitespace, `NSTextAttachment` bounds).
- Whether to compute the plan by probing TextKit (lay out candidate lines) rather than summing measured segments, and its cost against the 0.49ms median.

Answer: a recommended approach for break candidates and widths, with the script and feature coverage it gives, what still falls back to stock, and its cost. Cite Apple docs and, where useful, the 10 prototype (branch `prototype/10-ios-own-paragraph-component`).

## Answer

**Don't reproduce TextKit's line breaker. Find candidates with a Unicode line-break tokenizer, measure widths as additive logical-order advances, and let TextKit judge the plan: the 2a container, verify, one repair retry, then stock wrapping.** The exact TextKit oracle, `-[NSAttributedString lineBreakBeforeIndex:withinRange:]`, is macOS-only (it isn't in the iOS 27.2 SDK). Probing TextKit or Core Text line by line costs milliseconds.

- **Candidates:** `CFStringTokenizer` with `kCFStringTokenizerUnitLineBreak` per paragraph. Drop Hangul-internal breaks under `hangulWordPriority`. Both sides of U+FFFC are candidates.
- **Widths:** from the existing per-paragraph `CTLine`, prefix sums of per-character advances in logical order (`CTRunGetAdvances` + `CTRunGetStringIndices`), with trailing whitespace stripped. U+FFFC gets `NSTextAttachment.bounds.size.width`, and segments ending at a soft hyphen add the hyphen's width. This fixes bidi and attachments.
- **DP:** windowed to candidates that fit in `U`, O(k·m·c), so CJK's one candidate per character stays cheap.
- **On a mismatch:** keep TextKit's breaks up to the first disagreement, drop that candidate, re-plan, and lay out once more. If that also mismatches, stock wrapping.
- **Coverage:** Latin, explicit hyphens, CJK, Korean, bidi and inline attachments should balance. Thai-family scripts and kinsoku depend on the tokenizer agreeing with TextKit, which Apple doesn't document. Automatic hyphenation is off in RN iOS, since RN never sets `hyphenationFactor`.
- **Still stock:** tabs, `pushOut`, unresolved mismatches, infeasible plans, truncated text.
- **Cost (estimated, not measured):** about +0.05-0.15ms on the common path, so a median of roughly 0.55-0.65ms against 0.49ms. A repair adds about 0.2ms.
- **Later option:** a "veto-all and record" `shouldBreakLineByWord` delegate pass as an exact TextKit oracle. It relies on undocumented behaviour.

Full findings: [research/ios-plan-inputs.md](../research/ios-plan-inputs.md)
