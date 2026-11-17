import { requireNativeView } from 'expo';
import * as React from 'react';

import { ReactNativeTextBalancerViewProps } from './ReactNativeTextBalancer.types';

const NativeView: React.ComponentType<ReactNativeTextBalancerViewProps> = requireNativeView('ReactNativeTextBalancer');

export default function ReactNativeTextBalancerView(props: ReactNativeTextBalancerViewProps) {
  return <NativeView {...props} />;
}
