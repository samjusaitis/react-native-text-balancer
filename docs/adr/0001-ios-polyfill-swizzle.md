# iOS balancing is a polyfill for `textBreakStrategy="balanced"`, via a swizzle

The library ships no `Text` component of its own. Installing it makes RN's own `textBreakStrategy="balanced"` balance on iOS by swizzling the private `RCTTextLayoutManager` stack builder. Prototypes showed that every RN text path (measure, draw, hit-test, `onTextLayout`) goes through that one method, so balancing there keeps them all in agreement (branches `prototype/06-ios-exclusion-paths` and `prototype/08-ios-min-raggedness`). Installing it is the opt-in, so a process-wide change to RN's `Text` is the intended behaviour rather than a side effect.

## Considered Options

- **Own Fabric component behind a wrapper `Text` with `balance`:** built from subclasses of RN's paragraph classes, with no swizzle (branch `prototype/10-ios-own-paragraph-component`). It left RN's `Text` untouched and matched it on press handling, `selectable`, accessibility and `onTextLayout`. But it means a wrapper to keep level with RN `Text`, codegen, a build step, and two gaps: inline attachments didn't balance, and a root `onPress` highlighted like a span instead of the whole paragraph. It was the chosen design for a day, then dropped once the library became something you opt into by installing.
- **`patch-package` / config-plugin patch to RN:** prebuilt core (the default since RN 0.84) doesn't compile the patch.
- **Upstreaming balancing to RN:** not pursued. If RN ships its own balance (more likely as a `text-wrap: balance`-style style than through iOS `textBreakStrategy`), this package is deprecated.

## Consequences

We call a private method whose signature isn't a stable API. The swizzle checks
the selector and its type encoding, and on a mismatch it falls back to default
wrapping with one dev warning. Each RN minor still needs an iOS build in `verify:matrix`
before the tested range widens.
