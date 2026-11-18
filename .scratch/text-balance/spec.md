Status: ready-for-agent

# Spec: react-native-text-balancer, an iOS polyfill for `textBreakStrategy="balanced"`

Map: [map.md](map.md). Decision record: [ADR
0001](../../docs/adr/0001-ios-polyfill-swizzle.md). Terms:
[GLOSSARY.md](../../GLOSSARY.md) (**balance**, **stock wrapping**, **outermost Text**).

## Problem Statement

React Native's `Text` accepts `textBreakStrategy="balanced"`, but only Android honours it. On iOS the prop is parsed and then ignored, so headlines and short paragraphs wrap greedily. That leaves ragged lines and lone words on the last line, while the same component looks even on Android. iOS has no native API that balances lines. To get CSS `text-wrap: balance` behaviour on iOS today you need a JS measure loop, which causes layout jank, or your own text component, which diverges from RN `Text`.

## Solution

A small React Native library that, once installed, makes RN's own `textBreakStrategy="balanced"` balance on iOS, as it already does on Android. There's no new component, no new prop and no JS. Developers add the dependency, rebuild the iOS app, and write `<Text textBreakStrategy="balanced">` as they would for Android.

On iOS the library replaces RN's private TextKit stack builder at load time,
using method swizzling. For a paragraph whose `textBreakStrategy` is `balanced`,
it chooses **balanced breaks**: line breaks that minimise raggedness at the same line count stock
wrapping would use. It imposes those breaks on TextKit and checks the result. Any
paragraph it can't balance falls back to stock wrapping. On Android it does nothing.

It's distributed as a public GitHub repo, installed as a tag-pinned git dependency, with a README that lets anyone use it.

## User Stories

1. As an app developer, I want `textBreakStrategy="balanced"` to balance line breaks on iOS, so that my text looks the same as on Android without platform-specific code.
2. As an app developer, I want to enable it by installing a dependency and rebuilding, so that I don't need to change imports or wrap components.
3. As an app developer, I want to install it from a GitHub tag, so that I can pin a version without an npm release.
4. As an app developer, I want it to autolink in bare RN apps and Expo dev builds, so that I don't need a config plugin or manual native setup.
5. As an app developer, I want a `Text` without `textBreakStrategy="balanced"` to render exactly as stock RN, so that installing the library changes nothing I didn't opt into.
6. As an app developer, I want balanced text to keep the same number of lines as stock wrapping, so that layouts don't grow taller.
7. As an app developer, I want the `Text` box to keep its stock size while the lines inside it balance, so that surrounding layout is unaffected, as with CSS `text-wrap: balance`.
8. As an app developer, I want each paragraph (separated by newlines) balanced independently, so that a short paragraph isn't left ragged by a long one.
9. As an app developer, I want left, centred, right-aligned and RTL text to keep their alignment when balanced, so that balancing never shifts my text's edges.
10. As an app developer, I want `adjustsFontSizeToFit` to scale first and then balance, so that fitted headlines are balanced too.
11. As an app developer, I want text that fits within `numberOfLines` balanced to that many lines, so that clamped headlines still look even.
12. As an app developer, I want text that truncates at `numberOfLines` left exactly as stock, so that ellipsis behaviour is predictable.
13. As an app developer, I want nested `Text` spans with `onPress` to keep working, and their press highlight to hug the balanced lines, so that links and taps behave as before.
14. As an app developer, I want `selectable`, accessibility and VoiceOver to behave as stock, so that balancing doesn't regress accessibility.
15. As an app developer, I want `onTextLayout` to report the balanced lines, so that code that reads line metrics sees what's drawn.
16. As an app developer, I want inline views (a `View` inside `Text`) to balance correctly, so that icons and badges in headlines work.
17. As an app developer, I want CJK, Korean (both default and `hangul-word`), Thai, bidi (Arabic mixed with English), explicit hyphens and soft hyphens to balance correctly, so that localised text benefits too.
18. As an app developer, I want Japanese kinsoku rules respected, so that no line starts with closing punctuation or small kana.
19. As an app developer, I want a paragraph the library can't balance to render with stock wrapping and no error, so that balancing is never worse than not having it.
20. As an app developer, I want `lineBreakStrategyIOS="push-out"` to be ignored only where balancing applies, and kept on paragraphs that fall back, so that my settings aren't silently lost.
21. As an app developer, I want one dev warning if the library can't hook RN on my RN version, and stock layout otherwise, so that an RN upgrade never crashes my app.
22. As an app developer, I want balancing fast enough to run on every layout, so that scrolling and rendering aren't affected.
23. As an app developer, I want a repeated layout of the same text and width to reuse the earlier balanced breaks, so that drawing on the main thread is close to free.
24. As an app developer, I want Dynamic Type changes to rebalance automatically, so that balanced text stays correct at every text size.
25. As an app developer, I want the README to say exactly what balances and what falls back, so that I know what to expect without reading native code.
26. As an app developer, I want the README to tell me how to re-apply balancing on Android when I switch `textBreakStrategy` at runtime (by changing a `key`), so that I can work around RN's Android behaviour.
27. As an app developer on RN 0.85 or newer with the New Architecture, I want the library supported, so that I know which RN versions are safe.
28. As an app developer on an unsupported RN version, I want a clear build-time error, so that I don't ship a silently broken build.
29. As a third-party component author whose component already sets `textBreakStrategy="balanced"`, I want it to start balancing on iOS when the app installs this library, so that the prop means the same on both platforms.
30. As the maintainer, I want an example app with a self-checking test screen, so that I can confirm on a simulator that balancing works and stock text is unchanged.
31. As the maintainer, I want a local `verify:matrix` command that builds the library against every supported RN minor and the current RC, so that I know before a release which RN versions compile.
32. As the maintainer, I want a fast edit-and-run loop in the example app, so that I can change native code and see the result quickly.
33. As a contributor, I want the repo to explain what the library does and why it swizzles, so that I can understand it and contribute without the original context.

## Implementation Decisions

**Package shape.**

- It's a plain React Native library with iOS native code only, not an Expo module.
- The existing Expo module scaffold goes entirely: the module config, the Swift and Kotlin module and view stubs, the TypeScript module, view and web files, the internal module scripts, the `android/` directory and the Expo dependencies. The ticket 04 prototype swizzle file also goes, replaced by the real implementation.
- The package ships a `package.json`, the iOS sources, a podspec at the package root, and an RN CLI config that declares iOS only (`android: null`). There's no codegen, no `src/`, no build step and no TypeScript output.
- `peerDependencies`: `react-native >=0.85.0`. The native code fails the build with `#error` below RN 0.85, using RN's version macros. RN's `main` reports 1000.0 and must pass.
- Distribution: a public GitHub repo, installed as a git dependency pinned to a tag. It isn't published to npm. With no JS there's no `prepare` step.

**The iOS hook** (ADR 0001).

- From `+load`, replace the implementation of the private `-[RCTTextLayoutManager _textStorageAndLayoutManagerWithAttributesString:paragraphAttributes:size:]`. Every RN text path builds its TextKit 1 stack through this method: measure, `onTextLayout` lines, draw and hit-test. So one hook keeps them all consistent.
- **Guard:** swizzle only if the class and selector exist and the method's type encoding matches the expected signature. Otherwise leave RN untouched and log one dev warning per process.
- The replacement calls the original first, so the storage is already font-scaled by `adjustsFontSizeToFit`. It acts only when `paragraphAttributes.textBreakStrategy == Balanced`. Every other `Text` returns exactly what the original returned.
- RN's shared measure and lines caches key on `ParagraphAttributes`, which include `textBreakStrategy`. So balanced and stock layouts of the same string never share an entry.

**Choosing balanced breaks for one paragraph** (tickets 08, 11 and 14).

- Lay out at full width with unlimited lines to get the stock line count and group lines by paragraph. A paragraph with k ≤ 1 lines is left alone.
- **Break candidates:** `CFStringTokenizer` line-break units (UAX #14, including kinsoku and dictionary breaking for Thai).
- **Widths:** take logical-order advances from the paragraph's `CTRun` glyphs, prefix-summed by string index. Use the attachment `bounds` width for U+FFFC, strip trailing whitespace from each segment, and add the advance of `-` after a soft hyphen.
- **DP:** choose the k-line split that minimises Σ(U − wᵢ)² with no line wider than U, windowed for long CJK paragraphs.
- **Skip** (stock wrapping) when a paragraph contains a tab, when no k-line split fits (one segment wider than the box), or when the text truncates at `numberOfLines`. Text that fits within `numberOfLines` balances to that count.

**Imposing and checking the balanced breaks.**

- Swap RN's text container for an `NSTextContainer` subclass. It returns each balanced line's width from `lineFragmentRectForProposedRect:atIndex:…`, keyed by the line's start character index, plus 1–4pt of slack (half the gap to the next candidate). The last line of each paragraph keeps the full width. The container, and so the Yoga box, stays at the stock size.
- Line rects sit on the stock text's alignment side: trailing for left-aligned, leading for right-aligned and RTL, centred for centred text.
- **Check:** laid-out line starts must equal the balanced breaks. On a mismatch, run one repair retry. If that also fails, restore RN's container and leave that paragraph on stock wrapping. Fallback is per paragraph.
- **Push-out:** while checked balanced breaks are applied to a paragraph, clear `pushOut` from that paragraph's `lineBreakStrategy`. `standard` becomes `hangulWord`, and the hangul-word part is kept. On fallback, put back the original paragraph style. There's no warning. TextKit 1 currently ignores `pushOut` in RN, so this is about future-proofing more than visible behaviour.

**Break cache** (ticket 14).

- An `NSCache` (`countLimit` 256) inside the hook.
- **Key:** RN's input attributed string (compared with `isEqualToAttributedString:`, so string, fonts and paragraph style), width, `maximumNumberOfLines`, `adjustsFontSizeToFit`, and height when `adjustsFontSizeToFit` is on. Hash on string hash, width and max lines. Don't use `NSArray` hashing, which hashes by count.
- **Value:** per paragraph, the balanced line widths and side, or "stock", plus the ranges whose `pushOut` was cleared.
- **Height:** outside `adjustsFontSizeToFit` it isn't in the key, so measure (unbounded height) and draw (the measured frame) share an entry. A container too short for the balanced lines cuts them off and falls back to stock, so the value records the height its lines need, and a shorter container counts as a miss. An outcome where RN's height cut lines off isn't cached.
- There's no explicit invalidation, because the key covers everything the balanced breaks depend on (Dynamic Type changes the fonts). `NSCache` evicts under memory pressure.
- Measured effect: a hit costs 0.005ms, and mean overhead falls from 0.68ms to 0.25ms per build (prototype); in the build, 0.41ms to 0.17ms (ticket 05).

**Performance budget:** a Release median of about 0.5ms and a p90 of about 1.4ms per uncached build. Korean, Thai and Arabic paragraphs set the p90.

**Android:** no native code. The README documents RN's own behaviour: switching to `balanced` at runtime doesn't re-apply until the `Text` remounts, so change its `key`.

**API contract:** none beyond RN's own. `textBreakStrategy` is already typed on every platform through RN's `TextProps`. Only the outermost `Text`'s value is read; nested spans are ignored, as in stock RN.

**Example app:** keeps its Expo dev-client setup. It links the library straight from the repo root through its own RN CLI config (a dependency `root`), with no install copy or sync step, so a native rebuild picks up library edits. (Build ticket 01 replaced the planned `file:..` copy plus `sync` script, because bun's `file:` install copied the whole repo, example builds included.) Its main screen becomes the self-checking test screen (see Testing).

## Testing Decisions

- **One behaviour seam:** RN's own `Text` with `textBreakStrategy="balanced"`, observed through `onTextLayout`, in the example app's self-checking test screen.
  - Each sample renders three times at a fixed width and a fixed text size (`allowFontScaling={false}`, because the samples are tuned to wrap raggedly at it): stock (no `textBreakStrategy`), balanced, and a hidden twin with a non-balanced strategy (`highQuality`). The screen compares the lines and shows ✅ or ❌ per check.
  - A sample's expectation is one of:
    - balanced: same line count as stock, at least one line break moved, and the line widths vary less than stock's. The breaks have to move because a balanced line's narrowed fragment clips its trailing space, which stock's reported width includes, so identical lines can report a lower variance;
    - stock: identical lines to the stock render, for fallback cases;
    - unchanged: checked for every sample, the twin renders identically to stock, so the hook leaves every non-balanced `Text` alone.
  - **Dynamic Type samples** scale with the text size, so their wrapping changes with it. Each renders as stock, a balanced copy mounted since launch, and a hidden balanced copy remounted at each text size change with a string no other `Text` has had, so no cache can serve it. Checks that hold at any size:
    - rebalanced: the long-lived copy's lines match the fresh copy's;
    - no worse: same line count as stock, and either the same breaks (stock is already as even as it gets at this size, or the text fell back) or a lower width variance.
  - A human reads it on the iOS simulator, and on an Android emulator to check native `balanced`. There's no UI automation. `example/scripts/sweep-text-sizes.sh` steps an iOS simulator through every Dynamic Type size (`simctl ui content_size`) while the screen runs, and reads the summary it logs at each size.
- **Good tests check external behaviour only:** the lines RN reports and what's drawn, never the balanced breaks, the DP or the cache directly.
- **Sample set**, from tickets 06, 08, 10 and 14:
  - Latin headlines (left, centred, right, RTL) and a monospace headline;
  - a multi-paragraph sample and a long paragraph;
  - hyphenated compounds and a soft-hyphen word;
  - Japanese with closing punctuation, Chinese, and Korean in both modes;
  - Thai, and Arabic mixed with English;
  - a `View` inside `Text`;
  - nested pressable spans, to check the highlight hugs the lines and taps register by eye;
  - `adjustsFontSizeToFit`, plus `numberOfLines` that fits and that truncates;
  - fallback cases: a tab, a word wider than the box, and `push-out` on both a balancing paragraph and a falling-back one.
- **Gotcha:** give each sample a distinct string, for example by inserting U+2060. RN's text measure cache ignores `lineBreakStrategy`, so two `Text`s with the same string share one `onTextLayout` result.
- **Build gate:** `verify:matrix`, a local script run before each release and when a new RN minor or RC appears.
  - For each RN minor from 0.85 up, plus the current RC, it creates a fresh bare app, installs the package, runs `pod install` and a Debug simulator build.
  - It also builds the Expo example for iOS and Android.
  - It prints a pass/fail table. A full pass gates a release and widening the documented RN range.
- **No JS unit tests** (there is no JS) and no native unit tests. A lower seam beneath RN was considered and not chosen.
- **Prior art:** the probe and sample screens on the prototype branches (`prototype/06-ios-exclusion-paths`, `prototype/08-ios-min-raggedness`, `prototype/10-ios-own-paragraph-component`, `prototype/14-ios-plan-inputs-on-device`). Branch 14 holds the closest implementation of the inputs, the repair, the push-out rule and the cache, inside an own-component override of the same builder method.

## Out of Scope

- The old architecture (Paper).
- Web.
- Expo Go (Expo dev builds are supported).
- Balancing nested or inline `Text` spans separately; only the outermost `Text`'s `textBreakStrategy` is read.
- Guaranteed identical line breaks on iOS and Android; fonts and engines differ.
- A "did it balance" API or debug flag.
- Any Android native code, including a fix for RN's runtime-switch re-render bug.
- Fixing stock RN bugs found along the way: the misplaced RTL press highlight, the measure cache ignoring `lineBreakStrategy`, and TextKit 1 ignoring `pushOut`.
- Versioning, changelog, the release workflow and npm publishing.
- Upstreaming balancing to React Native.

## Further Notes

- **Known limits for the README:**
  - Paragraphs with tabs, a word wider than the box, or text that truncates use stock wrapping.
  - Thai-family scripts and kinsoku edge cases may fall back.
  - A paragraph can still end in an orphan if it falls back, or if its only break points force one.
  - A third-party `Text` that sets `balanced` will balance on iOS too.
  - A wrapped `Text` without a fixed width keeps the stock box width, which is the full available width, as stock RN and CSS `text-wrap: balance` do. The box doesn't shrink to the widest balanced line, so a view beside it doesn't move closer.
- **Future idea: a box that fits the balanced lines** (Sam, 2026-11-18). On iOS, the hook could make the container only as wide as the widest balanced line while RN measures, so RN reports that width. A view beside the text would then sit against it. Not built. It would make balanced text differ from stock RN and from CSS, so it would have to be opt-in or a deliberate change to this spec.
- **The swizzle depends on a private RN method.** Its signature has been unchanged from RN 0.85 through `main` (ticket 10). The type-encoding guard turns a future change into stock layout plus a warning, not a crash.
- **Decision detail lives in the tickets.** The Decisions so far in [map.md](map.md) link each one: 08 (algorithm), 11 and 14 (inputs, cost and cache), 12 (fallback and `numberOfLines` semantics, with the push-out amendment) and 15 (delivery). Tickets 09, 10 and 13 are partly superseded by 15.
