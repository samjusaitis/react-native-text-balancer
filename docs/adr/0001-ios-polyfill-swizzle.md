# iOS balancing is a polyfill for `textBreakStrategy="balanced"`, via a swizzle

The library ships no `Text` component of its own. Installing it makes RN's own `textBreakStrategy="balanced"` balance on iOS by swizzling the private `RCTTextLayoutManager` stack builder, the approach prototyped in tickets 04, 06 and 08. Installing it is the opt-in, so a process-wide change to RN's `Text` is the intended behaviour rather than a side effect.

## Considered Options

- **Own Fabric component behind a wrapper `Text` with `balance` (prototyped in ticket 10):** it leaves RN's `Text` untouched, but it means a wrapper to keep level with RN `Text`, codegen, a build step, and the parity gaps from ticket 10 (inline attachments, the root press highlight).
- **`patch-package` / config-plugin patch to RN:** prebuilt core (the default since RN 0.84) doesn't compile the patch.

## Consequences

We call a private method whose signature isn't a stable API. The swizzle checks
the selector and its type encoding, and on a mismatch it falls back to stock
wrapping with one dev warning. Each RN minor still needs an iOS build in `verify:matrix`
before the tested range widens.
