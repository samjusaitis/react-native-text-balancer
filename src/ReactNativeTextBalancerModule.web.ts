import { registerWebModule, NativeModule } from 'expo';

// ReactNativeTextBalancerModule is not available on the web platform.
class ReactNativeTextBalancerModule extends NativeModule<{}> {}

export default registerWebModule(ReactNativeTextBalancerModule, 'ReactNativeTextBalancerModule');
