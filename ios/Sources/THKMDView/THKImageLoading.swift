import UIKit
import CryptoKit

/// Loads an image for a Markdown `![]()` reference. `THKMDView.imageLoader` is settable, so a
/// host app that already uses Kingfisher/SDWebImage/Coil-equivalent can supply an adapter
/// instead of `DefaultTHKImageLoader`.
public protocol THKImageLoading {
    func load(url: URL) async -> UIImage?
}

/// Dependency-free default: `URLSession` + an in-memory `NSCache` + an on-disk cache under
/// the caches directory, keyed by a SHA-256 hash of the URL (via `CryptoKit`, a system
/// framework, not a third-party dependency).
public final class DefaultTHKImageLoader: THKImageLoading {
    private let session: URLSession
    private let memoryCache = NSCache<NSURL, UIImage>()
    private let diskCacheDirectory: URL
    private let fileManager = FileManager.default

    public init(session: URLSession = .shared) {
        self.session = session
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        diskCacheDirectory = caches.appendingPathComponent("THKMDView/ImageCache", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    public func load(url: URL) async -> UIImage? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }
        if Task.isCancelled { return nil }

        let diskURL = diskCacheFileURL(for: url)
        if let data = try? Data(contentsOf: diskURL), let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: url as NSURL)
            return image
        }
        if Task.isCancelled { return nil }

        guard let data = await fetchData(from: url), let image = UIImage(data: data) else {
            return nil
        }
        memoryCache.setObject(image, forKey: url as NSURL)
        try? data.write(to: diskURL, options: .atomic)
        return image
    }

    // URLSession's async `data(from:)` needs iOS 15; this package targets iOS 13, so the
    // completion-handler API is wrapped instead, with a cancellation handler that cancels the
    // underlying `URLSessionDataTask` when the surrounding `Task` is cancelled.
    private func fetchData(from url: URL) async -> Data? {
        final class TaskBox: @unchecked Sendable {
            private let lock = NSLock()
            private var task: URLSessionDataTask?
            private var cancelled = false

            func install(_ task: URLSessionDataTask) {
                lock.lock()
                self.task = task
                let shouldCancel = cancelled
                lock.unlock()
                if shouldCancel { task.cancel() }
            }

            func cancel() {
                lock.lock()
                cancelled = true
                let task = self.task
                lock.unlock()
                task?.cancel()
            }
        }
        let box = TaskBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                let task = session.dataTask(with: url) { data, response, _ in
                    guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: data)
                }
                box.install(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }

    private func diskCacheFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory.appendingPathComponent(hex)
    }
}
