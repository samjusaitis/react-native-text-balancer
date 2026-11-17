Type: research
Status: resolved
Assignee: Sam Jusaitis (claimed, research subagent)
Blocked by: none

## Question

Why does changing `textBreakStrategy` from `highQuality` back to `balanced` on an Android Fabric `Text` not re-apply (observed in [03 Android textBreakStrategy prototype](03-android-text-break-strategy-prototype.md)), while a `key` remount fixes it? Trace RN 0.88.1's Android path for the prop: props parsing into `ParagraphAttributes`, the measure/layout cache key (`TextLayoutManager`, `PreparedLayout`/`Layout` caches), and how `ReactTextView`/`PreparedLayoutTextView` applies `breakStrategy` on update. Is it a cache-key omission, a view-update omission, or a default-value comparison bug? Is it fixed upstream after 0.88.1? Decide: remount via `key` in the wrapper (cost: lost state, extra mount) vs. a targeted native fix or upstream patch. Cite RN source at the 0.88.1 tag (installed at `example/node_modules/react-native`).

## Answer

The bug is a skipped state update, not a cache key or serialisation problem. On Android with the default `enablePreparedTextLayout: false`, `ParagraphShadowNode::updateStateIfNeeded(const Content&)` returns early when the attributed string is unchanged. It never compares `paragraphAttributes` (RN 0.88.1 `ReactCommon/react/renderer/components/text/ParagraphShadowNode.cpp:174`). `ReactTextView` only gets `breakStrategy` from state, and `ReactTextViewManager` has no `@ReactProp` for `textBreakStrategy`. So a strategy-only change re-measures in Yoga but never reaches the view. The first toggle after mount most likely works by accident: the initial state's text fragments carry empty layout metrics, which makes the strings compare unequal. That part is inferred from source, not run. `main` and `v0.89.0-rc.1` still have the same check, and I found no upstream fix or PR.

Recommendation: keep the `key` remount in the wrapper, scoped to Android (`key={strategy}`). It's cheap for a leaf `Text`, and the toggle is rare. Separately, file the one-line upstream fix (also compare `state.paragraphAttributes`) and drop the `key` once a released RN includes it.

Details: [research/android-text-break-strategy-rerender.md](../research/android-text-break-strategy-rerender.md)
