Type: prototype
Status: resolved
Blocked by: 02

## Question

Does `textBreakStrategy="balanced"` on core `Text` produce the desired balanced result on Android? Use the test app with varied widths, multi-line text, mixed fonts, RTL and emoji, side by side with unbalanced text and a CSS-balanced reference. Decide: rely on the native strategy, or implement a custom native algorithm on Android too. Record observed gaps (e.g. versions, `numberOfLines`, quality vs. CSS balance).

## Answer

Rely on the native `textBreakStrategy="balanced"` on Android; no custom Android algorithm needed. Observed in the test app (human-tested by Sam):

- **Quality:** it distributes words evenly across lines, not just a max-width-style squeeze. A short last line holding a single word ('a') sat under a short line, and both were shorter than the longest line, so Android's balanced strategy minimises raggedness across lines rather than shrinking to a single narrowest width.
- **Caveat, prop updates don't re-apply:** toggling `balanced` → `highQuality` re-rendered correctly, but toggling back to `balanced` had no effect. Adding a `key` that changes with the prop forces a remount and fixes it. The library must handle this (remount via `key` in the wrapper, or fix natively).

Implications: iOS parity target is "even line lengths", so a plain binary search on max width may not match Android's look (feeds the Knuth-Plass question and parity). Not yet tested here: `numberOfLines`, RTL/emoji conclusions, OS-version differences.
