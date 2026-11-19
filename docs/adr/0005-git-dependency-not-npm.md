# A plain RN library installed from a GitHub tag, not published to npm

The package is a plain React Native library (iOS sources, a root podspec, and `react-native.config.js` with `android: null`), not an Expo module, and it's installed as a git dependency pinned to a release tag. It has no JS to build, so a git install needs no `prepare` step, and npm would mostly add semver ranges and discoverability. The library is mainly for a handful of the maintainer's own apps. Publishing to npm can be added later without changing the package.

## Considered Options

- **Expo module:** the original scaffold. None of the library uses the Expo Modules API, and a plain library autolinks in bare RN apps and Expo dev builds alike, with no config plugin.
