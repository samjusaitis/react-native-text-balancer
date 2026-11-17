// PROTOTYPE (ticket 10): without this file, Expo autolinking hides the package from RN's
// dependency list (it is an Expo module whose podspec is the same file), so RN codegen never
// reads package.json#codegenConfig and BalancedParagraph is not registered.
module.exports = {
  dependency: {
    platforms: {
      ios: {},
      android: null,
    },
  },
};
