# 05: Break cache

Spec: [spec.md](../../text-balance/spec.md) (Break cache). Detail: ticket 14 in [the map](../../text-balance/map.md).

**What to build:** repeated layouts of the same balanced text reuse the earlier balanced breaks. Drawing on the main thread and hit-testing cost almost nothing, while the lines stay identical.

- An `NSCache` (count limit 256) inside the hook.
- **Key:** RN's input attributed string (compared for equality, so string, fonts and paragraph style), width, max lines, `adjustsFontSizeToFit`, and height when `adjustsFontSizeToFit` is on. Don't hash a collection by count.
- **Value:** per paragraph, the balanced line widths and side or "stock", plus the ranges whose `pushOut` was cleared, so that a hit clears them again.
- There's no explicit invalidation. Dynamic Type changes fonts, and therefore the key.

**Blocked by:** 03, 04.

**Status:** ready-for-agent

- [ ] Every test-screen sample shows the same result and the same lines with the cache on and off.
- [ ] In a Release build, cache hits cost about 0.005ms, and the mean balancing overhead per build drops to roughly a third of uncached.
- [ ] Changing Dynamic Type rebalances balanced text correctly.
