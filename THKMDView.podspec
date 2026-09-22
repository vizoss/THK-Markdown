Pod::Spec.new do |s|
  s.name             = 'THKMDView'
  s.version          = '0.1.0'
  s.summary          = 'A streaming-Markdown UIView for LLM chat bubbles.'
  s.description      = <<-DESC
    THKMDView is a UIKit view that renders Markdown (CommonMark + GFM: tables,
    strikethrough, task lists) for LLM chat message bubbles inside a UITableView/
    UICollectionView cell, including live updates as SSE deltas arrive via
    appendMarkdownChunk. This CocoaPods distribution renders Markdown with Maaku
    (a Swift wrapper around cmark-gfm); the Swift Package Manager distribution of
    the same package uses swift-markdown instead. Public API and visual behavior
    are meant to be equivalent between the two.
  DESC
  s.homepage         = 'https://github.com/vizoss/THK-Markdown'
  s.license          = { type: 'MIT', file: 'LICENSE' }
  s.author           = 'THK'
  s.source           = { git: 'https://github.com/vizoss/THK-Markdown.git', tag: "v#{s.version}" }

  s.ios.deployment_target = '13.0'
  s.swift_versions        = ['5.0']

  s.source_files     = 'ios/Sources/THKMDView/**/*.swift'
  s.exclude_files    = 'ios/Sources/THKMDView/SPM/**/*.swift'

  # THKMermaidView.swift needs these at runtime for its Mermaid WKWebView (mermaid.min.js
  # v11.17.2, MIT-licensed — see ios/Sources/THKMDView/mermaid.min.js's own header comment
  # for provenance). `s.resources` alone would copy them straight into the consuming app's
  # main bundle, which works for a static-library integration but not a dynamic-framework
  # one; `resource_bundles` instead produces a dedicated `THKMDView.bundle` that
  # `THKMermaidView.resourceURL(name:ext:)` can find via `Bundle(for:)` either way. The SPM
  # distribution ships the same two files through `Package.swift`'s `resources:` instead.
  s.resource_bundles = {
    'THKMDView' => [
      'ios/Sources/THKMDView/mermaid_template.html',
      'ios/Sources/THKMDView/mermaid.min.js'
    ]
  }

  s.dependency 'Maaku', '~> 0.9'

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'ios/Tests/THKMDViewCocoaPodsTests/**/*.swift'
  end
end
