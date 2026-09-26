Pod::Spec.new do |s|
  s.name = 'THKMDView'
  s.version = '1.0.3'
  s.summary = 'A streaming-Markdown UIView for LLM chat bubbles.'
  s.description = 'Precompiled UIKit renderer using swift-markdown, identical to the SPM implementation.'
  s.homepage = 'https://github.com/vizoss/THK-Markdown'
  s.license = { type: 'MIT', file: 'LICENSE' }
  s.author = 'THK'
  # Publish this asset before distributing this podspec. Git-only installation no
  # longer builds the library: the repository does not contain the binary artifact.
  s.source = { http: "https://github.com/vizoss/THK-Markdown/releases/download/#{s.version}/THKMDView-#{s.version}.zip" }
  s.ios.deployment_target = '13.0'
  s.swift_versions = ['5.0']
  s.vendored_frameworks = 'THKMDView.xcframework'
  s.preserve_paths = 'THIRD_PARTY_LICENSES'
  s.frameworks = 'UIKit', 'WebKit'
end
