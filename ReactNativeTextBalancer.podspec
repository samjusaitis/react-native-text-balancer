require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'ReactNativeTextBalancer'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = "#{package['description']} — Expo native module for iOS and tvOS."
  s.license        = package['license']
  s.authors        = package['author']
  s.homepage       = package['homepage']
  s.platforms      = {
    :ios => '16.4',
    :tvos => '16.4'
  }
  s.swift_version  = '5.9'
  s.source         = { git: 'https://github.com/samcodefish/react-native-text-balancer.git', tag: "#{s.version}" }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  # PROTOTYPE (ticket 10): RN Fabric headers for the BalancedParagraph component.
  install_modules_dependencies(s)

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }

  s.source_files = "ios/**/*.{h,m,mm,swift,hpp,cpp}"
end
