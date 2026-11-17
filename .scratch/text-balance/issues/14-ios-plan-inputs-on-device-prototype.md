Type: prototype
Status: resolved
Blocked by: none
Assignee: Claude (session local_5d964b03 side session)

## Question

Do the plan inputs chosen in [11 iOS plan inputs research](11-ios-plan-inputs-research.md) hold up on a real iOS build, and with the real cost known, does the min-raggedness plan need caching? If it does, where is the cache and what is its key?

Build on the `BalancedParagraph` prototype from [10](10-ios-own-paragraph-component-prototype.md) (branch `prototype/10-ios-own-paragraph-component`). Swap its plan inputs for 11's ([research/ios-plan-inputs.md](../research/ios-plan-inputs.md)):

- break candidates from `CFStringTokenizer` `kCFStringTokenizerUnitLineBreak`;
- logical-order widths from per-glyph `CTRun` advances, with U+FFFC set to the attachment's `bounds` width, trailing whitespace stripped, and a `-` advance added after a soft hyphen;
- the DP windowed for CJK;
- one repair retry, then stock wrapping;
- paragraphs containing `\t` skipped; `pushOut` paragraphs planned with `pushOut` cleared only while a verified plan is applied, restored on fallback (rule amended by [15](15-delivery-polyfill-grilling.md); replaces "skip `pushOut`").

Check, on RN 0.88.1 in the example app (Release build for timings):

1. **Agreement with TextKit:** log mismatches and repair rate for one sample each of hyphenated compounds, Japanese with closing punctuation (kinsoku), Chinese, Korean with and without `lineBreakStrategyIOS="hangul-word"`, Thai, Arabic mixed with English, a `View` inside `Text`, and a word with a soft hyphen. Note which samples fall back to stock wrapping.
2. **The open facts from 11 §7:** what TextKit 1 does at a soft hyphen with hyphenation off; any extra spacing around attachments; the default `usesDefaultHyphenation` on the paragraph styles RN builds.
3. **Cost:** median and p90 per stack build, compared with 10's 0.49ms median and 11's 0.55-0.65ms estimate. Count how often one paragraph is planned again for the same string, width and attributes across measure, draw, hit-test and `onTextLayout`.
4. **Caching:** from 3, decide whether caching is needed. If it is, choose its placement (shadow node state, the `RCTTextLayoutManager` subclass, or RN's own text layout cache), its key (string plus attributes, width, and paragraph attributes), and how it is invalidated. Prototype it if the choice isn't obvious from the numbers.

If the tokenizer disagrees too often on any script, record whether the delegate oracle (11 §5) is worth prototyping, or whether that script stays on stock wrapping.

## Answer

**Ticket 11's inputs hold on device, cost no more than 10's, and the plan needs a cache: an `NSCache` inside the (swizzled) stack builder, content-addressed, so there is nothing to invalidate.** Accepted by Sam, 2026-11-18. Measured on RN 0.88.1, iOS 27.2 simulator (iPhone 18 Pro), on the `BalancedParagraph` build from 10. The builder override is the same method the polyfill swizzles ([15](15-delivery-polyfill-grilling.md)), so every number carries over.

1. **Agreement with TextKit: 0 mismatches.** About 1,700 builds over 14 samples × 320/240/180pt (Debug with diagnostics, plus Release). Every break stock TextKit made at full width was a tokenizer candidate.
   - Balanced: hyphenated compounds, Japanese (no line starts with closing punctuation or small kana), Chinese, Korean default and `hangul-word` (word-only breaks), Thai, Arabic mixed with English, a `View` inside `Text` (10's gap is fixed), soft hyphens, and the Latin samples from 08/10.
   - Stock wrapping: paragraphs with a tab (skipped by design), and a single word wider than the box (no k-line plan fits; TextKit character-wraps).
   - Predicted line widths match TextKit to 0.00pt (Latin, CJK, Korean, attachment lines) and 0.37pt on lines ending at a soft hyphen.
   - The repair retry never fired. Forced with bogus mid-word candidates (`-TBFakeCands`), it repaired 38 builds; 39 fell back because a second bogus candidate was picked (one retry, by design).
   - The delegate oracle (11 §5) isn't worth prototyping.
2. **Open facts from 11 §7.**
   - With hyphenation off, TextKit 1 **does** break at U+00AD and draws a visible `-` there. The tokenizer offers the candidate, and adding the `-` advance matches TextKit within 0.37pt.
   - Attachments get no extra spacing (predicted vs laid-out width 0.00pt).
   - `usesDefaultHyphenation` is NO and `hyphenationFactor` 0 on RN's paragraph styles and on the layout manager.
   - Stock RN bug found on the way: `TextMeasureCache`'s layout-wise attribute comparison ignores `lineBreakStrategy` (and `lineBreakMode`). Two `Text`s with the same string and font, one with `lineBreakStrategyIOS`, share one measurement and one `onTextLayout` result, while draw (uncached) uses the real strategy. Test samples need distinct strings (U+2060 works).
3. **Cost (Release, balancing overhead per stack build, n=549 each, same screen):**

   | Inputs | median | p90 | mean |
   |---|---|---|---|
   | ticket 11 (new) | 0.483ms | 1.40ms | 0.68ms |
   | ticket 10 (old, `-TBOldInputs`) | 0.507ms | 1.41ms | 0.67ms |
   | new, Latin-only samples | 0.39ms | 0.60ms | |

   - Below 11's 0.55-0.65ms estimate. 10's 0.49ms was a Debug figure. The input pass is 0.075ms (old 0.111ms), the DP 0.003ms; the rest is TextKit layout. The p90 comes from Korean, Thai and Arabic paragraphs (1.0-1.5ms).
   - Repeats: RN caches `measure` and `getLines` (its `TextMeasureCache` / `LineMeasureCache`), but not `drawAttributedString`, `drawingFrameForAttributedString`, `getEventEmitterWithAttributeString` (hit-test) or `getRect`. Per mounted paragraph that is 3 builds for the same string and width: measure (background), `onTextLayout` lines (background), draw (**main thread**). A remount or redraw adds 1 draw build; each touch on a pressable paragraph adds 1 hit-test build.
4. **Caching: needed, prototyped (`-TBCache`).**
   - **Placement:** an `NSCache` (`countLimit` 256) inside the swizzled `RCTTextLayoutManager` stack builder. Under the polyfill this is the only option: shadow-node state is RN's, and RN's text caches hold only `TextMeasurement`/lines, which draw and hit-test never read.
   - **Key:** RN's input `NSAttributedString` (`isEqualToAttributedString:`, so string, fonts and paragraph style including `lineBreakStrategy`), width, `maximumNumberOfLines`, `adjustsFontSizeToFit`, plus height when `adjustsFontSizeToFit` (scaling depends on it). Hash on string hash, width and `maxLines`.
   - **Value:** per-line widths and strip side, or "stock"; plus the paragraph ranges whose `pushOut` the plan clears, so a hit clears them again.
   - **Invalidation:** none; the key is everything the plan depends on (Dynamic Type changes the fonts, so the key changes). `NSCache` evicts under memory pressure.
   - **Result:** 369 of 549 builds hit, at 0.005ms (p90 0.008ms); mean overhead per build 0.68 → 0.25ms, and draw on the main thread pays almost nothing. Lines identical with and without the cache (66/66).
   - **Under the swizzle:** RN's shared caches key on `ParagraphAttributes`, whose `==` and hash include `textBreakStrategy`, so balanced and stock `Text` never share an entry.
5. **Push-out rule (from 15):** a `push-out` paragraph balances at all three widths with no mismatch, `pushOut` cleared only while the verified plan is applied (also on cache hits). A tab paragraph with `push-out` falls back to stock with `pushOut` still on the style. **TextKit 1 ignores `pushOut` in RN:** stock `Text` with and without `push-out` gives identical lines at every width, orphans included, so restoring it keeps stock behaviour exactly but does not remove the orphan.

Prototype: throwaway branch `prototype/14-ios-plan-inputs-on-device` (commit 1ce2314, on 10's e1865ed; not on main). `ios/BalancedParagraph.mm` has the inputs, repair, push-out rule and cache, with launch args `-TBOldInputs`, `-TBDiag`, `-TBFakeCands`, `-TBCache`; `example/App.tsx` has the ticket 14 samples.

Gotchas: `CI=1` Metro doesn't watch files, so restart it (`--clear`) after JS edits. `NSArray` hashes by count, so don't use it as a cache key.
