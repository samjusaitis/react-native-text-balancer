# Android: why `textBreakStrategy` updates don't re-apply on Fabric

Date researched: 2026-11-17. Question (ticket [07](../issues/07-android-text-break-strategy-rerender-research.md)): on Android Fabric, why does toggling `textBreakStrategy` from `highQuality` back to `balanced` have no effect, while a `key` remount fixes it? Is it fixed upstream?

Primary source: RN 0.88.1 as installed at `example/node_modules/react-native` (paths below are relative to that folder). Upstream checked on `facebook/react-native` `main` and `v0.89.0-rc.1` via the GitHub API on 2026-11-17.

## Verdict

- **Root cause: a state-update omission in the C++ `ParagraphShadowNode`, not a cache key or a serialisation bug.** On the default (non-prepared-layout) path, `ParagraphShadowNode::updateStateIfNeeded(const Content&)` skips the state update when the attributed string is unchanged. It never compares `paragraphAttributes` (`ReactCommon/react/renderer/components/text/ParagraphShadowNode.cpp:174`). A change to `textBreakStrategy` alone leaves the text unchanged, so no new `ParagraphState` is committed, and the Android view never hears about it.
- **The Android view only gets `textBreakStrategy` through state.** `ReactTextViewManager` has no `@ReactProp` for `textBreakStrategy` (it has them for `numberOfLines`, `ellipsizeMode`, `adjustsFontSizeToFit`, `includeFontPadding`, `android_hyphenationFrequency`, `textAlignVertical`, etc.; `ReactTextViewManager.kt:238-398`). So the prop diff that Fabric does send is dropped on the floor for this key.
- **Not fixed upstream.** `main` and `v0.89.0-rc.1` have the same check on the Android branch.
- **Recommendation:** keep the `key` remount in the wrapper. It is cheap for a leaf `Text`, it works on every RN version, and `balance` rarely toggles at runtime. A one-line upstream patch is worth filing, but the library can't depend on it.

## 1. The C++ side serialises and compares the prop correctly

Ruled out as causes:

- **Parsing:** `textBreakStrategy` is parsed into `ParagraphAttributes` with `convertRawProp(..., sourceParagraphAttributes.textBreakStrategy, defaultParagraphAttributes.textBreakStrategy)` (`ReactCommon/react/renderer/attributedstring/conversions.h:1026-1031`). The default is `HighQuality` (`ParagraphAttributes.h:47`). Setting `balanced` after `highQuality` parses to `Balanced`; nothing collapses it to the default.
- **Equality and hash:** `ParagraphAttributes::operator==` includes `textBreakStrategy` (`ParagraphAttributes.cpp:17-28`), and so does `std::hash<ParagraphAttributes>` (`ParagraphAttributes.h:99-112`).
- **Serialisation:** `toMapBuffer(ParagraphAttributes)` always writes `PA_KEY_TEXT_BREAK_STRATEGY` (key 2) as a string, with no "omit if default" branch (`conversions.h:1154`, `1164-1167`). Java reads key 2 in `TextLayoutManager.kt:92` and maps `"balanced"` to `Layout.BREAK_STRATEGY_BALANCED` (`TextAttributeProps.kt:595-601`).
- **Measure cache:** the C++ `TextMeasureCache` keys include `paragraphAttributes` in both equality and hash (`ReactCommon/react/renderer/textlayoutmanager/TextMeasureCache.h:273-321`). So Yoga measurement does use the new strategy. Only the drawn view is stale.

## 2. The state update is skipped

`ParagraphShadowNode::layout()` picks one of two `updateStateIfNeeded` overloads (`ParagraphShadowNode.cpp:299-343`):

- With `enablePreparedTextLayout` on, the templated overload compares size, attributed string **and** `paragraphAttributes` (`ParagraphShadowNode.cpp:154-156`).
- With it off, it calls `updateStateIfNeeded(content)`, which compares **only** the attributed string:

```cpp
// ParagraphShadowNode.cpp:168-183 (RN 0.88.1)
void ParagraphShadowNode::updateStateIfNeeded(const Content& content) {
  ...
  if (state.attributedString == content.attributedString) {
    return;
  }
  setStateData(ParagraphState{content.attributedString, content.paragraphAttributes, textLayoutManager_});
}
```

`enablePreparedTextLayout` defaults to `false` in 0.88.1 (`ReactCommon/react/featureflags/ReactNativeFeatureFlagsDefaults.h:200-202`; `ReactAndroid/.../internal/featureflags/ReactNativeFeatureFlagsDefaults.kt:110`), and the example app doesn't override it. So the app runs the second overload.

## 3. The view applies `breakStrategy` only from state

- `ReactTextViewManager.updateState` builds a `ReactTextUpdate` from the state MapBuffer, reading `PA_KEY_TEXT_BREAK_STRATEGY` (`ReactTextViewManager.kt:133-192`, read at `178-181`).
- `updateExtraData` passes it to `ReactTextView.setText(ReactTextUpdate)` (`ReactTextViewManager.kt:96-100`), which calls `setBreakStrategy` only if the value differs (`ReactTextView.java:346-348`). That path is correct. It just never runs, because no new state arrives.
- No `@ReactProp("textBreakStrategy")` exists in `views/text` (the only reference outside the state path is the constant `ViewProps.TEXT_BREAK_STRATEGY`, `uimanager/ViewProps.kt:109`). So there's no props-path fallback, unlike `numberOfLines` (`ReactTextViewManager.kt:255`).

Result: Yoga sizes the box with the new strategy, but the `TextView` keeps drawing with the old `breakStrategy`. A `key` change creates a new shadow node family, so the mount carries fresh initial state with the new value. That's why remounting fixes it.

## 4. Why the first toggle worked (likely, not verified on device)

The prototype saw `balanced → highQuality` re-apply and `highQuality → balanced` fail. The asymmetry comes from how `AttributedString` equality works:

- `Fragment::operator==` compares `parentShadowView.layoutMetrics` as well as the string and text attributes (`ReactCommon/react/renderer/attributedstring/AttributedString.cpp:32-43`). For raw text, `parentShadowView` is a snapshot of the paragraph node itself (`BaseTextShadowNode.cpp:51`).
- `getContent()` builds that snapshot during measurement, before the node's new layout is set (`ParagraphShadowNode.cpp:70-93`). On first mount the node has empty layout metrics, so the initial state's fragments carry empty metrics.
- On the first toggle, the props-changed clone carries the previous frame's metrics. They differ from the empty ones, so the attributed strings compare unequal, and the state update (with the new `paragraphAttributes`) goes through **by accident**.
- On the second toggle, both sides carry the same frame. The test app fixes `width: w`, and both strategies usually give the same line count, so the height matches too. The strings compare equal and the update is skipped.

Predicted behaviour: only the first toggle after mount applies. Later toggles apply only when the paragraph's frame size changes (for example, a different line count). This fits the ticket 03 observation, but I didn't run it.

## 5. Upstream status

- `main` (2026-11-17) and `v0.89.0-rc.1`: the Android branch of `updateStateIfNeeded(const Content&)` still returns early on `state.attributedString == content.attributedString`. It doesn't check `paragraphAttributes` (`packages/react-native/ReactCommon/react/renderer/components/text/ParagraphShadowNode.cpp:229-244` on `main`). The non-Android branch also compares `layoutSize`, but not `paragraphAttributes`.
- Recent commits to that file don't address it: `0e041ddf8f` (#59357), `db5c52de8b` (#59285, re-land of #59063, "Keep paragraph content and measured layouts across unchanged clones"), `b97bd12bc4` (#59162), `d026c0fa9a` (#59049). #59285 removes spurious state updates for clones **without** new props. It doesn't touch the props-changed case. If anything, fewer spurious updates means fewer accidental fixes.
- GitHub search on `react/react-native` for `textBreakStrategy` and `paragraphAttributes` found no open issue or PR about this. The closest is #38347 (Paper `TextInput` default, unrelated).
- With `enablePreparedTextLayout` on, the templated overload does compare `paragraphAttributes`, and the `PreparedLayout` carries `textBreakStrategy` (`ReactTextViewManager.kt:197-220`). So that path should be immune. This is inferred from source, not run.

## 6. Options

| Option | Works on | Cost |
|---|---|---|
| `key` remount in the wrapper (current workaround) | every RN version | New native view on toggle. Loses view-local state such as text selection. Negligible for a leaf `Text`, and toggling `balance` is rare. |
| Upstream patch: add `&& state.paragraphAttributes == content.paragraphAttributes` at `ParagraphShadowNode.cpp:174` | future RN only | One line. Also fixes other state-only paragraph attributes (e.g. `minimumFontSize`). Consumers can't get it until they upgrade, or via `patch-package`. |
| Library-side "nudge" (force the attributed string to differ) | every version | Hacky. Relies on internal equality details that #59063/#59285 are actively changing. Not recommended. |
| Enable `enablePreparedTextLayout` | apps that opt in | App-wide experimental flag. A library can't set it for consumers. |

Recommendation: ship the `key` remount, scoped to Android and to the strategy value (`key={strategy}`), and file the one-line upstream fix with a repro. Drop the `key` once a released RN version includes the fix.

## Unverified

- The first-toggle asymmetry explanation in section 4 is from reading the source, not observed with logging.
- That `enablePreparedTextLayout: true` avoids the bug.
- That no upstream issue exists. GitHub search is keyword-based and may have missed one.
