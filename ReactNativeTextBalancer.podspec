require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = 'ReactNativeTextBalancer'
  s.version      = package['version']
  s.summary      = package['description']
  s.license      = package['license']
  s.authors      = package['author']
  s.homepage     = package['homepage']
  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { git: 'https://github.com/samjusaitis/react-native-text-balancer.git', tag: "v#{s.version}" }
  s.source_files = 'ios/**/*.{h,m,mm}'
  s.private_header_files = 'ios/**/*.h'

  # React Native's C++ text headers (ParagraphAttributes) for the TextKit hook.
  install_modules_dependencies(s)
end
