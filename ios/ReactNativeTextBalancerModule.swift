import ExpoModulesCore

public class ReactNativeTextBalancerModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ReactNativeTextBalancer")

    View(ReactNativeTextBalancerView.self) {
    }
  }
}
