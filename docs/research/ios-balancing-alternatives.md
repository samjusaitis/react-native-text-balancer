# iOS balancing alternatives to the tailIndent spike

> A design-time research note, kept as written. Numbers like 04, 08 or 10 name the prototypes listed in [the research index](README.md#prototypes). What shipped is in [the ADRs](../adr/).

Date researched: 2026-11-17. Question: which iOS approaches balance RN Fabric `Text` line breaks without the two trade-offs found by the `tailIndent` prototype (04): (1) the pressed nested-span highlight runs to the box edge, past the narrowed line; (2) no `adjustsFontSizeToFit` support.

Builds on [ios-native-balancing.md](ios-native-balancing.md) (no built-in iOS balance API; the RN pipeline overview). This note does not repeat that work.

Sources:
- RN source: the installed **0.88.1** package at `example/node_modules/react-native` (version checked in its `package.json`). Line numbers below are from those files. Short names:
  - `RTLM` = `ReactCommon/react/renderer/textlayoutmanager/platform/ios/react/renderer/textlayoutmanager/RCTTextLayoutManager.mm`
  - `RPCV` = `React/Fabric/Mounting/ComponentViews/Text/RCTParagraphComponentView.mm`
  - `FS` = `Libraries/Text/Text/NSTextStorage+FontScaling.m`
- Apple docs: fetched as the doc-JSON `.md` pages; URLs are given inline.

**Nothing here has been run.** The research was read-only (no build, no simulator), so every "should" below about TextKit behaviour is reasoning from the docs and source, and each shortlist item lists what the prototype must check first.

## Verdict

**Keep the swizzled hook. Replace the negative `tailIndent` with `NSTextContainer.exclusionPaths` (one trailing strip, or one strip on each side for centred text). Apply them *after* RN's font scaling has run.** This should remove both trade-offs with a small change to the spike. For Android-like minimum raggedness, the next step up is a per-line width plan, using either an `NSTextContainer` subclass or the `shouldBreakLineByWordBeforeCharacterAtIndex` delegate veto. Any of these approaches can later go upstream into RN as an iOS implementation of `textBreakStrategy="balanced"`.

## 1. Where the press highlight comes from

1. `RCTAttributedTextUtils.mm:330-331` sets the `IsHighlighted` attribute (`RCTAttributedStringIsHighlightedAttributeName`) on the runs of the pressed span, when `TextAttributes.isHighlighted` is true.
2. `-[RCTTextLayoutManager drawAttributedString:paragraphAttributes:frame:drawHighlightPath:]` (`RTLM:130-321`) builds the stack through the private `_textStorageAndLayoutManagerWithAttributesString:...` (`RTLM:135-138`). It draws the glyphs at `frame.origin` (`RTLM:152-153`). Then, for each highlighted range (`RTLM:290-320`), it calls
   `enumerateEnclosingRectsForGlyphRange:range withinSelectedGlyphRange:range inTextContainer:` and appends `bezierPathWithRoundedRect:CGRectInset(rect, -2, -2) cornerRadius:2` for each rect.
3. `-[RCTParagraphTextView drawRect:]` (`RPCV:438-472`) puts that path in a `CAShapeLayer` (25% black), positioned at `frame.origin` (`RPCV:465`).

**Why it overflows under `tailIndent`.** RN passes the range as the *selected* range, so it gets selection rectangles. Apple: "If a selected range is given … the rectangles returned are correct for drawing the selection" ([enumerateEnclosingRects](https://developer.apple.com/documentation/uikit/nslayoutmanager/enumerateenclosingrects(forglyphrange:withinselectedglyphrange:in:using:).md); the AppKit sibling [rectArray(forGlyphRange:withinSelectedGlyphRange:…)](https://developer.apple.com/documentation/appkit/nslayoutmanager/rectarray(forglyphrange:withinselectedglyphrange:in:rectcount:).md) adds "Contiguous lines can share an enclosing rectangle, and lines broken into several fragments have a separate enclosing rectangle for each fragment"). When a highlighted span continues onto the next line, the selection rect for the earlier line runs to the end of that line's **line fragment rect**, not to the last glyph. A paragraph-style indent narrows where glyphs are set *inside* the fragment, but the fragment still spans the full container width. So the highlight runs to the box edge. The docs don't spell out this indent/fragment relationship; it is inferred from the spike's observed result plus the selection semantics. Stock RN has the same effect, but it is barely visible there because greedy lines nearly fill the box.

**Consequence:** any fix that leaves the line fragment rects full-width, including tailIndent and a pure break-veto, keeps the overflow. Fixes must narrow the fragment rects themselves, or clip the path afterwards.

The same rect source feeds `getRectWithAttributedString:` (`RTLM:479-517`, which takes only the first rect per range via `*stop = YES`), used by the accessibility provider (`RCTParagraphComponentAccessibilityProvider.mm:77`) for link frames. Narrowing the fragments fixes those frames too.

## 2. Where font scaling happens (and why balancing after it is safe)

- `_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:` (`RTLM:418-447`): container `initWithSize:size`, `lineFragmentPadding = 0`, `lineBreakMode` and `maximumNumberOfLines` from paragraph attributes, then `RCTApplyBaselineOffset`. If `adjustsFontSizeToFit` is set, it then calls `[textStorage scaleFontSizeToFitSize:size minimumFontSize:maximumFontSize:]` (`RTLM:440-444`).
- `scaleFontSizeToFitSize:` (`FS:18-62`) returns early if the text already fits. Otherwise it binary-searches a font ratio, rewriting `NSFontAttributeName` on the storage in place (`FS:109-129`). "Fits" (`FS:64-107`) means no truncated glyphs on the last line **and** `usedRectForTextContainer` ≤ `size` in both axes.
- Callers pass different sizes. Measure passes `{maxWidth, CGFLOAT_MAX}` (`RTLM:53`), so scaling in measure only triggers through truncation with `numberOfLines`. Draw, hit-test and the rect query pass `frame.size`; getLines passes the given size. Each call scales independently. That is RN's existing behaviour, not ours.

**The ordering is "scale, then balance".** The spike's hook already calls the original first (`PrototypeBalanceSwizzle.mm:balancedBuild`), so the storage it gets back is already scaled. Balancing keeps the line count by construction, so the used height stays the same. (This assumes uniform line heights; mixed font sizes could shift height slightly.) The used width only shrinks. So the scaled text still "fits" and the scale decision stays valid. Two things the spike must change:

1. Remove the `adjustsFontSizeToFit` bail-out.
2. Measure line counts the way the hook's container does. The spike's `lineCount()` builds a fresh unlimited container. When `maximumNumberOfLines > 0` and the full-width layout is truncated (that is, it has a `truncatedGlyphRangeInLineFragmentForGlyphAtIndex` hit, like `FS:82`), **skip balancing**: a truncated paragraph has no stable target line count. Otherwise cap the target at `maximumNumberOfLines`.

CSS has no analogue for auto-fit, so this ordering is a product decision. It is the only one that keeps RN's fit guarantee: balancing first and then scaling would let the scaler re-wrap at the full width.

## 3. Candidate mechanisms (TextKit 1 primitives)

| Mechanism | Narrows fragment rects? (fixes highlight) | Per-line widths? (min-raggedness) | Applied from the existing hook? |
|---|---|---|---|
| Negative `tailIndent` (spike) | No | No (one inset per paragraph) | Yes, attribute edit |
| `NSTextContainer.exclusionPaths` | **Yes** | Only by stair-stepping rects (fragile) | **Yes**, set on the returned container |
| `NSTextContainer` subclass overriding `lineFragmentRect(forProposedRect:at:…)` | **Yes** | **Yes** (receives the line's start char index) | Yes, but must swap the container on the layout manager |
| `NSLayoutManagerDelegate` `shouldSetLineFragmentRect:…` | Can trim width after typesetting | No | Yes, but the delegate is `weak`, so it needs a retained owner |
| `NSLayoutManagerDelegate` `shouldBreakLineByWordBeforeCharacterAtIndex:` | No (geometry unchanged) | **Yes** (veto all but planned breaks) | Same `weak` delegate caveat |
| Narrow the container `size.width` | Yes | No | No: measure reports `size.width = textContainer.size.width` when wrapped (`RTLM:571-573`), so the Yoga box shrinks; centred/right/RTL text then needs an origin offset in every consumer |

Doc facts behind the table:

- [exclusionPaths](https://developer.apple.com/documentation/uikit/nstextcontainer/exclusionpaths.md) (iOS 7+): "When the layout manager proposes a line fragment rectangle intersecting one of the regions defined by the exclusion paths, the text container returns an adjusted line fragment rectangle excluding that region."
- [lineFragmentRect(forProposedRect:at:writingDirection:remaining:)](https://developer.apple.com/documentation/uikit/nstextcontainer/linefragmentrect(forproposedrect:at:writingdirection:remaining:).md) (iOS 7+): it takes the line's `characterIndex` and the `baseWritingDirection`, and "This method can be overridden by subclasses for further text container region customization."
- [isSimpleRectangularTextContainer](https://developer.apple.com/documentation/uikit/nstextcontainer/issimplerectangulartextcontainer.md): it is false when there are exclusion paths, a non-zero `maximumNumberOfLines` (RN already sets this for `numberOfLines`), or an override of the method above. So RN already uses the non-simple layout path in some cases; the cost of joining it is not documented.
- [layoutManager(_:shouldSetLineFragmentRect:lineFragmentUsedRect:baselineOffset:in:forGlyphRange:)](https://developer.apple.com/documentation/uikit/nslayoutmanagerdelegate/layoutmanager(_:shouldsetlinefragmentrect:linefragmentusedrect:baselineoffset:in:forglyphrange:).md) (iOS 9+): you "may modify this rectangle"; the used rect "must be equal to `lineFragmentRect` or wholly contained by it"; "It is your responsibility to ensure that the modified rectangles remain valid". It runs after the line is typeset, so it cannot change breaks.
- [layoutManager(_:shouldBreakLineByWordBeforeCharacterAt:)](https://developer.apple.com/documentation/uikit/nslayoutmanagerdelegate/layoutmanager(_:shouldbreaklinebywordbeforecharacterat:).md) (iOS 7+): returning false means "the layout manager should find the next break point opportunity before `charIndex`".
- [NSLayoutManager.delegate](https://developer.apple.com/documentation/uikit/nslayoutmanager/delegate.md) is `weak`. The hook creates a fresh layout manager per call, so the delegate has to be kept alive by something, for example an associated object on the layout manager or text storage.

## 4. Ranked shortlist (ready to prototype)

### 1. Exclusion-path strip in the existing hook, after scaling (recommended next spike)

What: in `balancedBuild`, after `gOriginal(...)` returns, run the same binary search, but cap the target at `maximumNumberOfLines` and skip balancing if truncated. Then set `textContainer.exclusionPaths` instead of editing paragraph styles:
- start/left-aligned LTR: one rect `{W - inset, 0, inset, H}`;
- right-aligned, or RTL natural (RN resolves natural alignment per writing direction, `RCTAttributedTextUtils.mm:222-226`, `541-567`): the strip on the left;
- centred: `inset/2` on each side;
- justified: a trailing strip; lines justify to the balanced width.

`H` must be finite: measure's container height is `CGFLOAT_MAX` (`RTLM:53`). Use, for example, the full-width used height plus a margin, or a large constant.

Removes: (1) the highlight overflow, because fragment rects now end at the strip, so selection rects stop there; it also fixes the accessibility link frames. (2) `adjustsFontSizeToFit`, which works because balancing runs on the scaled storage.

Keeps: the Yoga box at full width (the container size is unchanged, so `RTLM:571-573` still reports `W`), hit-testing and `onTextLayout` (all through the same hook), and RTL/centring.

Introduces: all paragraphs share one strip, as with tailIndent. A multi-paragraph string with mixed alignment can't be served by one strip; fall back to no balance, or use #2. The non-simple-rectangular layout path may cost more (not measured).

Prototype checks: highlight across a wrapped nested span (LTR, centred, RTL); `adjustsFontSizeToFit` + `numberOfLines`; exclusion height in the measure path; per-call cost (still needs the (string, width, attrs) cache noted in 04).

### 2. Per-line width plan for minimum raggedness

Two equivalent ways to force a precomputed break plan (Knuth-Plass-style minimum raggedness over word widths, which gives parity with Android `balanced`):

- **2a. `NSTextContainer` subclass.** Override `lineFragmentRectForProposedRect:atIndex:writingDirection:remainingRect:`. From the line's start `characterIndex`, look up the planned line width and return a rect of that width (plus a small epsilon), positioned by alignment and writing direction inside the full-width container. In the hook, swap it in for RN's container: copy `size`, `lineFragmentPadding`, `lineBreakMode` and `maximumNumberOfLines`, then `removeTextContainerAtIndex:0` / `addTextContainer:`. This gives per-line fragment geometry, so the highlight is also tight. It handles multiple paragraphs, because the index tells you which paragraph you are in.
- **2b. Break veto plus #1's strip.** A delegate's `shouldBreakLineByWordBeforeCharacterAtIndex:` returns NO for every candidate not in the plan. The greedy breaker then backs off to the planned break. Combine it with an exclusion strip at the plan's widest line so the highlight stays tight. The delegate must be retained (it is `weak`).

Removes: both 04 trade-offs, as in #1, plus the max-width-squeeze limitation (monospace 240pt).

Introduces: a line-breaking pass in the library. It must mirror TextKit's break opportunities and measured widths: use `CTTypesetterSuggestLineBreak`, or the same TextKit stack, to measure the candidates. There is a risk that the plan and TextKit disagree; the epsilon in 2a or the veto in 2b absorbs most of it. There is more code and more cost per layout. Hyphenation and `NSParagraphStyle.lineBreakStrategy` (`pushOut`) interact with it in ways not yet known.

Order: try 2b first (smallest change, no geometry). Use 2a if the veto misbehaves.

### 3. Keep tailIndent, patch only the highlight

- Delegate `shouldSetLineFragmentRect:` trims each fragment's width to the used extent. This is clean for start-aligned LTR. Centred and right-aligned text would need the fragment **origin** moved, and glyph locations are relative to the fragment origin, so moving it shifts glyphs: unverified and likely wrong.
- Or isa-swizzle the returned `NSLayoutManager` to a subclass that clips `enumerateEnclosingRects…` output to each line's used rect.

Removes: (1) only. (2) is fixed by the same "after scaling" change as #1, independent of the mechanism. Introduces a second patch point. #1 is strictly simpler, so rank this only as a fallback if exclusion paths misbehave.

### 4. Not recommended

- **Narrow `size.width` in the hook:** it shrinks the Yoga box (`RTLM:571-573`), which is not CSS-like. Non-start alignments then need `frame.origin` offsets in draw (`RTLM:152-153`), hit-test (`RTLM:462-464`, `RPCV:317`) and highlight (`RPCV:465`), none of which the hook controls.
- **JS-only `maxWidth` loop:** already rejected in the earlier research (render pass per step, box shrinks).

## 5. Hook surface

1. **Swizzle `_textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:` (current).** It is still the single convergence point in 0.88.1: measure `RTLM:54`, drawing frame `RTLM:85`, draw `RTLM:135`, lines `RTLM:370`, hit-test `RTLM:454`, rects `RTLM:485`. The private selector could be renamed in any RN release. Keep the `+load` guard (it already logs and no-ops when the method is missing) and add a CI check against each supported RN version. The flag stays `textBreakStrategy="balanced"`. `ParagraphAttributes.textBreakStrategy` is documented as "(Android only)" (`ParagraphAttributes.h:44-47`), but it is a parsed field, and it is part of `ParagraphAttributes`' hash (`ParagraphAttributes.h:105`). The measure cache keys on paragraph attributes (`TextLayoutManager.mm` measure / `measureLines` cache keys), so balanced and unbalanced results don't collide.
2. **No public subclass seam.** `TextLayoutManager` hard-codes `[RCTTextLayoutManager new]` (`TextLayoutManager.mm:19`). `ParagraphComponentDescriptor` takes the C++ `TextLayoutManager` from the context container (`BaseParagraphComponentDescriptor.h:25`). Subclassing `RCTParagraphComponentView` would only reach draw and hit-test, not Yoga measure. I did not check whether an app can register its own `TextLayoutManager` under `TextLayoutManagerKey`; even if it can, the class is concrete C++, not designed for substitution.
3. **Custom Fabric component:** loses nested `Text`, press handling, accessibility and attachments unless they are reimplemented (as noted in the earlier research). Not worth it.
4. **Upstream / patch-package:** the natural RN change is roughly 20 lines in `_textStorageAndLayoutManagerWithAttributesString` (exclusion strip after the scaling block) when `textBreakStrategy == Balanced`, plus updating the "(Android only)" docs. No new prop or C++ plumbing is needed. This is the stable endgame; the swizzle can ship meanwhile and turn itself off once RN implements it.

## 6. Gaps / unverified

- **No experiment was run** (the constraints were no build and no simulator). Unverified in particular: that selection rects stop at exclusion-path edges, as the docs imply; that the 04 overflow came from a span wrapping across lines rather than a single-line span; the cost of the non-simple-rectangular path; and how `drawingFrameForAttributedString` (feature flag `enableIOSCompressedTextFrameAdjustment`, `RTLM:72-128`) interacts with exclusion paths.
- Apple docs don't state how paragraph indents relate to line fragment rect bounds. The explanation in §1 is inferred from the selection-rect semantics and the spike's observation.
- Whether `scaleFontSizeToFitSize:`'s width comparison (`FS:91`, `FS:102`) could pick a different scale if the exclusion were set *before* scaling. This is moot if the strip is applied after, as recommended.
- The `isHighlighted` set/clear path on press (which shadow-node update toggles it) was not traced past `RCTAttributedTextUtils.mm:330`; it doesn't affect the geometry question.
