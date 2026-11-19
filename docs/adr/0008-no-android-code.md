# No Android code, and RN's runtime-switch bug is left to users

On Android the library does nothing: RN's native `textBreakStrategy="balanced"` already minimises raggedness. RN has a bug where switching a `Text` to `balanced` at runtime doesn't take effect, because `ParagraphShadowNode::updateStateIfNeeded` skips the update when only `paragraphAttributes` change ([research](../research/android-text-break-strategy-rerender.md)). The library doesn't work around it. The docs tell people to change the `Text`'s `key` along with the strategy, which only matters if they switch it at runtime.

## Considered Options

- **A wrapper `Text` that adds the `key` remount:** part of the own-component design, dropped with it ([ADR 0001](0001-ios-polyfill-swizzle.md)). With no JS in the package there's nowhere to put it.
- **A native fix:** it would mean an Android module for a one-line RN bug that's better fixed upstream (also compare `paragraphAttributes`).
