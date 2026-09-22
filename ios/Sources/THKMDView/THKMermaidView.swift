import UIKit
import WebKit

/// Renders a `.diagram(mermaidSource:)` segment (see `THKRenderSegment`) as an actual Mermaid
/// flowchart via an embedded `WKWebView` running a vendored `mermaid.min.js` — a deliberate,
/// scoped exception to this package's general "no WebView" stance (RESEARCH.md §2 kept WebView
/// as a documented escape hatch for exactly this kind of node type). Analogous in role to
/// `THKTableView`: a dedicated view bound in `THKMDView.swift`'s segment-building code, sized
/// to its own real rendered content rather than a fixed guess (`onSizeChange` mirrors
/// `THKAsyncImageTextAttachment`'s pattern).
public final class THKMermaidView: UIView {
    /// Fired once the WebView reports its diagram's real size (or the fallback text's size
    /// changes), so `THKMDView` can invalidate its own intrinsic content size — the same
    /// "tell the container its cached size is stale" handshake `THKAsyncImageTextAttachment`
    /// uses for images.
    public var onSizeChange: (() -> Void)?

    private let webView: WKWebView
    private let fallbackTextView = UITextView()
    private var messageHandlerProxy: ScriptMessageHandlerProxy?
    private var renderedSize = CGSize(width: 0, height: 160)
    private var currentSource: String?
    private var theme: THKMDTheme = .default

    // WKUserContentController retains whatever object is added as a script message handler,
    // so adding `self` directly would create a retain cycle (view -> configuration ->
    // controller -> handler -> view) that `stop()`/`removeScriptMessageHandler` alone can't
    // break before it's called. This weak-referencing proxy is the indirection that keeps the
    // strong reference off `THKMermaidView` itself.
    private final class ScriptMessageHandlerProxy: NSObject, WKScriptMessageHandler {
        weak var target: THKMermaidView?
        init(target: THKMermaidView) { self.target = target }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.handleScriptMessage(message)
        }
    }

    public override init(frame: CGRect) {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)
        commonInit(configuration: configuration)
    }

    public required init?(coder: NSCoder) {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(coder: coder)
        commonInit(configuration: configuration)
    }

    private func commonInit(configuration: WKWebViewConfiguration) {
        let proxy = ScriptMessageHandlerProxy(target: self)
        messageHandlerProxy = proxy
        configuration.userContentController.add(proxy, name: Self.messageHandlerName)

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        fallbackTextView.isHidden = true
        fallbackTextView.isEditable = false
        fallbackTextView.isSelectable = true
        fallbackTextView.isScrollEnabled = false
        fallbackTextView.backgroundColor = .clear
        fallbackTextView.textContainerInset = .zero
        fallbackTextView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallbackTextView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),

            fallbackTextView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fallbackTextView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallbackTextView.topAnchor.constraint(equalTo: topAnchor),
            fallbackTextView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Called by `THKMDView` when (re)binding this view to a `.diagram` segment. Skips a
    /// reload when `source` is unchanged from the last call — every debounced streaming
    /// re-render rebuilds segments even when a given diagram's fenced block hasn't grown, and
    /// reloading an unchanged WebView would flash/re-render the SVG for nothing.
    public func configure(source: String, theme: THKMDTheme) {
        self.theme = theme
        guard source != currentSource else { return }
        currentSource = source
        fallbackTextView.isHidden = true
        webView.isHidden = false
        loadDiagram(source: source)
    }

    private func loadDiagram(source: String) {
        guard
            let templateURL = Self.resourceURL(name: "mermaid_template", ext: "html"),
            let templateHTML = try? String(contentsOf: templateURL, encoding: .utf8)
        else {
            showFallback(source: source, note: "diagram template resource missing")
            return
        }
        guard let sourceData = try? JSONEncoder().encode([source]) else {
            showFallback(source: source, note: "diagram failed to render")
            return
        }
        let base64 = sourceData.base64EncodedString()
        let html = templateHTML.replacingOccurrences(of: "THK_MERMAID_SOURCE_B64", with: base64)
        webView.loadHTMLString(html, baseURL: templateURL.deletingLastPathComponent())
    }

    private func handleScriptMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "size":
            guard
                let width = body["width"] as? Double, width > 0,
                let height = body["height"] as? Double, height > 0
            else { return }
            applyRenderedSize(CGSize(width: width, height: height))
        case "error":
            showFallback(source: currentSource ?? "", note: "diagram failed to render")
        default:
            break
        }
    }

    private func applyRenderedSize(_ size: CGSize) {
        let maxWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let scale = size.width > maxWidth ? maxWidth / size.width : 1
        renderedSize = CGSize(width: min(size.width, maxWidth), height: (size.height * scale).rounded(.up))
        invalidateIntrinsicContentSize()
        onSizeChange?()
    }

    // Invalid Mermaid syntax (or a missing/failed-to-load template) falls back to the raw
    // ```mermaid source as plain monospaced text with a short note, rather than leaving a
    // blank/broken WebView on screen.
    private func showFallback(source: String, note: String) {
        webView.isHidden = true
        fallbackTextView.isHidden = false
        let result = NSMutableAttributedString(
            string: "⚠️ \(note)\n\n",
            attributes: [.font: UIFont.systemFont(ofSize: theme.bodyFontSize), .foregroundColor: theme.bodyTextColor]
        )
        result.append(NSAttributedString(
            string: "```mermaid\n\(source)\n```",
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: theme.codeFontSize, weight: .regular),
                .foregroundColor: theme.codeTextColor
            ]
        ))
        fallbackTextView.attributedText = result
        invalidateIntrinsicContentSize()
        onSizeChange?()
    }

    /// Must be called before this view (or its owning segment) is discarded — mirrors
    /// `THKAsyncImageTextAttachment.cancelLoading()`/`THKMDView.reset()`'s existing reuse-
    /// safety guarantee for in-flight image loads and streamed text. Stops any in-flight load
    /// and removes the script message handler explicitly rather than relying solely on
    /// `deinit`, since `WKUserContentController` holding a strong reference to the (proxied)
    /// handler would otherwise keep the whole view graph alive longer than the segment that
    /// owns it.
    public func stop() {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        messageHandlerProxy = nil
        currentSource = nil
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
    }

    public override var intrinsicContentSize: CGSize {
        if !fallbackTextView.isHidden {
            let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
            let fitting = fallbackTextView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: UIView.noIntrinsicMetric, height: fitting.height)
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: renderedSize.height)
    }

    private static let messageHandlerName = "thkMermaid"

    // SPM ships `mermaid_template.html`/`mermaid.min.js` via `Bundle.module` (declared as
    // `.copy` resources in Package.swift); CocoaPods has no `Bundle.module` equivalent, so the
    // podspec declares the same two files as an `s.resource_bundles` entry named "THKMDView",
    // which CocoaPods packages as a `THKMDView.bundle` alongside (static lib) or inside
    // (dynamic framework) whatever bundle `Bundle(for: THKMermaidView.self)` resolves to
    // either way — hence the fallback lookup below instead of assuming one location.
    // `internal` (not `private`) so the SPM/CocoaPods test targets — `@testable import
    // THKMDView` — can assert the bundled resources are actually found at runtime on both
    // distributions, not just that THKMermaidView compiles. A missing/misconfigured resource
    // bundle (the CocoaPods path especially — see the podspec's `s.resource_bundles` comment)
    // otherwise fails silently at runtime instead of at build time.
    static func resourceURL(name: String, ext: String) -> URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: name, withExtension: ext)
        #else
        let classBundle = Bundle(for: THKMermaidView.self)
        if let bundleURL = classBundle.url(forResource: "THKMDView", withExtension: "bundle"),
           let resourceBundle = Bundle(url: bundleURL) {
            return resourceBundle.url(forResource: name, withExtension: ext)
        }
        return classBundle.url(forResource: name, withExtension: ext)
        #endif
    }
}
