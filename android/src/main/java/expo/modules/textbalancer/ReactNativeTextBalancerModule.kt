package expo.modules.textbalancer

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ReactNativeTextBalancerModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ReactNativeTextBalancer")

    View(ReactNativeTextBalancerView::class) {
    }
  }
}
