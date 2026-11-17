Type: prototype
Status: resolved
Assignee: Sam Jusaitis (claimed)
Blocked by: none

## Question

Should iOS balance by **minimum raggedness** (even out every line, like Android's native `balanced`) instead of the current max-width squeeze? Prototype a per-line break plan in the 06 spike (branch `prototype/06-ios-exclusion-paths`): compute breaks that minimise the variance of line widths at a fixed line count, then impose them, via the `shouldBreakLineByWordBeforeCharacterAtIndex:` delegate veto plus the exclusion strip, or an `NSTextContainer` subclass returning per-line widths (see [05 research](../research/ios-balancing-alternatives.md)). Compare side by side on iOS against the squeeze and against Android `balanced` screenshots of the same samples (the monospace 240pt case stays ragged under the squeeze). Decide: squeeze, min-raggedness, or a user-facing option. Record the cost against the ~1ms baseline, and whether multi-paragraph text gets per-paragraph plans for free.

## Answer

**Minimum raggedness, with no user-facing squeeze option.** Sam's verdict, after reviewing squeeze vs. min-raggedness on the iOS Simulator next to Android `balanced` (RN 0.88.1, iOS 27.2 simulator, Debug build).

How the spike does it ([ios/PrototypeBalanceSwizzle.mm](../../../ios/PrototypeBalanceSwizzle.mm) on the prototype branch):

- Same swizzled hook as 06, still applied after RN's font scaling. Min-raggedness is flagged per `Text` by `android_hyphenationFrequency="full"`, a prototype-only switch.
- Count lines at full width (untruncated, unbounded height) and group them by paragraph (`paragraphRangeForRange:` on each line's start index).
- For each paragraph with k > 1 lines: candidate breaks are the starts of words after spaces. Word-boundary x offsets come from a single `CTLine` of the paragraph, so trailing spaces are excluded. A DP picks the k-line plan that minimises the sum of (U - w_i)^2, which is the same as minimising line-width variance. No line may be wider than U.
- Impose the plan with approach 2a from 05: an `NSTextContainer` subclass swapped in for RN's container. It overrides `lineFragmentRectForProposedRect:atIndex:...` to return each planned line's width, keyed by the line's start character index, plus a slack of 1-4pt (half the gap to the next word). The rect is positioned like the 06 strip side: trailing, leading for right-aligned/RTL, centred. The last line of each paragraph keeps the full width. The `shouldBreakLineByWordBeforeCharacterAtIndex:` veto (2b) wasn't needed.
- Verify that the laid-out line starts equal the plan. On a mismatch, put RN's container back and fall back to the squeeze. There were 0 mismatches across all samples.
- If no k-line plan fits, for example when one word is wider than the box, that paragraph keeps the stock full-width breaks.

Comparison:

- **Quality:** the same as the squeeze on most proportional samples. Clearly better on the monospace 240pt case (the reason for this ticket), the Paragraph sample at 240pt, and all multi-paragraph widths. Long headline at 180pt: roughly a tie (min-raggedness ends on a shorter line, the squeeze starts with short lines).
- **Android parity:** iOS min-raggedness matches Android `balanced` line for line on the centred 240pt, monospace 240pt, Paragraph 180pt and multi-paragraph 180pt samples. Remaining differences come from font metrics (Roboto vs. SF give different line counts).
- **Cost:** median 0.59ms per stack build (mean 0.69ms, p90 1.49ms, n=113), against the squeeze's median 1.26ms (mean 1.53ms, p90 3.65ms, n=81) in the same run, and the ~1ms baseline. That's about two layouts plus one `CTLine` per paragraph, against the squeeze's ~10 binary-search layouts. The (string, width, attrs) cache is still worth having, since it is recomputed on every measure/draw/hit-test.
- **Multi-paragraph: per-paragraph plans come for free.** The line start index identifies the paragraph. The squeeze shares one strip across paragraphs, so a short paragraph stays unbalanced, and at 180pt it leaves an orphaned "lines.".
- **Squeeze bug found:** with a single long word that fits the box (320pt), the squeeze narrows below the word's width and TextKit char-wraps it mid-word while keeping 2 lines. Min-raggedness keeps the word whole.
- **Highlight, hit-test and font scaling:** each line fragment now hugs its line, so the pressed-span highlight is tighter than the squeeze's common edge. LTR, centred and right-aligned text are correct. RTL shows the stock RN glyph/character bug from 06. Taps on the span register and an off-span tap is ignored; `onTextLayout` reports 194 / 227 / 200. `adjustsFontSizeToFit` and `numberOfLines` behave as in 06.

Not covered: hyphen and CJK break opportunities (only spaces are candidates; a different break by TextKit would show up as a mismatch and fall back), and bidi-mixed paragraphs (widths are `|x(end) - x(start)|` on one `CTLine`).

Prototype code (throwaway branch `prototype/08-ios-min-raggedness`, commit b7a4acd; not on main): `ios/PrototypeBalanceSwizzle.mm` and the stacked squeeze/min-raggedness samples, the multi-paragraph sample and the mode-aware probes in `example/App.tsx`.

Gotcha: the Android example build has dev-server port 8099 compiled in (another project's Metro). Point it elsewhere with the app's `debug_http_host` shared pref plus `adb reverse`.
