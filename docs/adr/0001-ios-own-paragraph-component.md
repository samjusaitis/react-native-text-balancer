# iOS balancing uses our own paragraph component, not a swizzle of RN's text layout

The library's `Text` must run alongside React Native's `Text` without changing it in any way. So on iOS we don't swizzle or patch `RCTTextLayoutManager`, even though the prototypes (tickets 04–08) showed that a swizzle gated on `textBreakStrategy="balanced"` works and is less code. Instead `balance` on iOS renders our own Fabric host component. Its shadow node, `TextLayoutManager`, `RCTTextLayoutManager` and paragraph view are subclasses of RN's, so only our instances balance and our measure cache is separate.

## Considered Options

- **Swizzle gated on `textBreakStrategy="balanced"`:** a plain RN `Text` with that prop would also balance on iOS.
- **Swizzle gated on a private sentinel** (for example `minimumFontScale={-1}`): it still modifies RN's class process-wide, and RN 0.89 starts reading `minimumFontScale` on iOS.
- **`patch-package` / config-plugin patch to RN:** it modifies RN, and since RN 0.84 prebuilt core is the default, so the patch isn't compiled unless the app builds RN from source.
- **Upstreaming iOS `textBreakStrategy="balanced"`:** not pursued. If RN ever ships native balancing, this package is deprecated instead.

## Consequences

We compile against RN's internal C++ paragraph classes, which aren't a stable API, so each RN minor needs a CI build and the supported range has a floor (RN ≥ 0.85).
