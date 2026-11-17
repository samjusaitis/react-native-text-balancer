import { NativeModule, requireNativeModule } from 'expo';

declare class ReactNativeTextBalancerModule extends NativeModule<{}> {}

export default requireNativeModule<ReactNativeTextBalancerModule>('ReactNativeTextBalancer');
