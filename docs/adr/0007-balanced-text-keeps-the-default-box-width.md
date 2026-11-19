# Balanced text keeps the default box width

Balancing narrows the lines inside a `Text`, but the box keeps the size default wrapping gives it. A wrapping `Text` without a fixed width stays as wide as the space it's given, as RN does without the library and as CSS `text-wrap: balance` does, so nothing around it moves when balancing turns on. (RN's measure sets a wrapped `Text`'s width to the container width, not the widest line, so default wrapping doesn't hug its lines either.)

## Considered Options

- **Shrink the box to the widest balanced line:** the hook could report a narrower width while RN measures, so a view beside the text sits against it. Not built, because balanced text would then lay out differently from RN without the library and from CSS. It could come back as an opt-in.
