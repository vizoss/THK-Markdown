import UIKit
import WebKit

/// Offline math rasterizer. A single hidden WKWebView is shared, bounded by an
/// 8 MB bitmap cache and at most 64 pending expressions. No message views retained.
@MainActor
final class THKMathEngine: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = THKMathEngine()
    private let requestSink: (([String: Any]) -> Void)?
    // Internal transport injection keeps coalescing/cancellation tests independent of WebKit.
    init(requestSink: (([String: Any]) -> Void)? = nil) {
        self.requestSink = requestSink
        super.init()
    }
    final class Result: NSObject {
        let image: UIImage
        let descent: CGFloat
        init(_ image: UIImage, descent: CGFloat) { self.image = image; self.descent = descent }
    }
    private let cache = NSCache<NSString, Result>()
    private var cacheLimitBytes = 8 * 1024 * 1024

    func configureCache(maxBytes: Int) {
        precondition(maxBytes >= 0, "maxBytes must be nonnegative")
        cacheLimitBytes = maxBytes
        cache.removeAllObjects()
        cache.totalCostLimit = maxBytes
    }

    func clearCache() { cache.removeAllObjects() }
    private var web: WKWebView?
    private var loaded = false
    private struct Pending {
        let key: String
        let request: [String: Any]
        var subscribers: [String: CheckedContinuation<Result?, Never>]
    }
    private var waiting: [String: Pending] = [:]
    private var inFlight: [String: String] = [:]
    internal var pendingSubscriberCount: Int { waiting.values.reduce(0) { $0 + $1.subscribers.count } }

    nonisolated static func source(_ url: URL) -> String? {
        guard url.scheme == "thk-math", ["inline", "display"].contains(url.host ?? "") else { return nil }
        var encoded = String(url.path.dropFirst()).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard encoded.count <= 12000, let data = Data(base64Encoded: encoded) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func render(_ url: URL, theme: THKMDTheme) async -> Result? {
        guard let source = Self.source(url), !Task.isCancelled else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        theme.bodyTextColor.resolvedColor(with: .current).getRed(&r, green: &g, blue: &b, alpha: &a)
        let color = "rgba(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)),\(a))"
        let size = max(1, min(96, theme.bodyFontSize * theme.mathScale))
        let scale = UIScreen.main.scale
        let key = "\(url)|\(size)|\(color)|\(scale)"
        if let result = cache.object(forKey: key as NSString) { return result }
        guard (inFlight[key] != nil || waiting.count < 64),
              waiting.values.reduce(0, { $0 + $1.subscribers.count }) < 256, start() else { return nil }
        let subscriber = UUID().uuidString
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                if let id = inFlight[key] {
                    waiting[id]?.subscribers[subscriber] = continuation
                    return
                }
                let id = UUID().uuidString
                let request: [String: Any] = ["id": id, "tex": source, "display": url.host == "display", "size": size, "color": color, "scale": scale]
                waiting[id] = Pending(key: key, request: request, subscribers: [subscriber: continuation])
                inFlight[key] = id
                if loaded { send(request) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.finish(id, result: nil) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let id = self.inFlight[key] else { return }
                self.waiting[id]?.subscribers.removeValue(forKey: subscriber)?.resume(returning: nil)
            }
        }
    }

    private func start() -> Bool {
        if requestSink != nil { loaded = true; return true }
        if web != nil { return true }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: THKMathEngine.self)
        #endif
        guard let url = bundle.url(forResource: "math_template", withExtension: "html") else { return false }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "math")
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        view.navigationDelegate = self
        web = view
        cache.totalCostLimit = cacheLimitBytes
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return true
    }
    private func send(_ request: [String: Any]) {
        if let requestSink { requestSink(request); return }
        guard let data = try? JSONSerialization.data(withJSONObject: request), let json = String(data: data, encoding: .utf8) else { return }
        web?.evaluateJavaScript("window.renderMath(\(json))")
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        for (_, entry) in waiting { send(entry.request) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "math")
        web = nil; loaded = false
        for id in Array(waiting.keys) { finish(id, result: nil) }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let json = message.body as? String, let data = json.data(using: .utf8),
              let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let id = value["id"] as? String else { return }
        guard let png = value["png"] as? String, let bytes = Data(base64Encoded: png),
              let bitmap = UIImage(data: bytes), let width = value["width"] as? Double,
              let height = value["height"] as? Double, let descent = value["descent"] as? Double,
              width > 0, height > 0, width <= 4096, height <= 2048, let cg = bitmap.cgImage else { finish(id, result: nil); return }
        let image = UIImage(cgImage: cg, scale: CGFloat(cg.width) / width, orientation: .up)
        finish(id, result: Result(image, descent: descent))
    }
    internal func finish(_ id: String, result: Result?) {
        guard let entry = waiting.removeValue(forKey: id) else { return }
        inFlight.removeValue(forKey: entry.key)
        if let result {
            let cost = (result.image.cgImage?.bytesPerRow ?? 0) * (result.image.cgImage?.height ?? 0)
            if cacheLimitBytes > 0 && cost <= cacheLimitBytes {
                cache.setObject(result, forKey: entry.key as NSString, cost: cost)
            }
        }
        for continuation in entry.subscribers.values { continuation.resume(returning: result) }
    }
}
