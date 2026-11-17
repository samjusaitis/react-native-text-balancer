// Reexport the native module. On web, it will be resolved to ReactNativeTextBalancerModule.web.ts
// and on native platforms to ReactNativeTextBalancerModule.ts
export { default } from './ReactNativeTextBalancerModule';
export { default as ReactNativeTextBalancerView } from './ReactNativeTextBalancerView';
export * from './ReactNativeTextBalancer.types';
