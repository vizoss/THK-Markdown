import Foundation

public protocol DebounceScheduling {
    func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> Cancellable
}

public protocol Cancellable {
    func cancel()
}

public final class DispatchQueueScheduler: DebounceScheduling {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> Cancellable {
        let item = DispatchWorkItem(block: work)
        queue.asyncAfter(deadline: .now() + interval, execute: item)
        return DispatchWorkItemCancellable(item: item)
    }
}

private final class DispatchWorkItemCancellable: Cancellable {
    private let item: DispatchWorkItem
    init(item: DispatchWorkItem) { self.item = item }
    func cancel() { item.cancel() }
}

/// Accumulates streamed Markdown text and coalesces rapid appends into a single
/// debounced render callback. Kept free of UIKit so it can be unit tested in isolation
/// and driven by a fake scheduler for deterministic, sleep-free tests.
public final class StreamingMarkdownBuffer {
    public private(set) var text: String = ""
    public var debounceInterval: TimeInterval
    public var onRender: ((String) -> Void)?

    private let scheduler: DebounceScheduling
    private var pendingWork: Cancellable?

    public init(debounceInterval: TimeInterval = 0.032, scheduler: DebounceScheduling = DispatchQueueScheduler()) {
        self.debounceInterval = debounceInterval
        self.scheduler = scheduler
    }

    public func setFull(_ markdown: String) {
        pendingWork?.cancel()
        pendingWork = nil
        text = markdown
        onRender?(text)
    }

    public func append(_ chunk: String) {
        text += chunk
        scheduleRender()
    }

    public func reset() {
        pendingWork?.cancel()
        pendingWork = nil
        text = ""
    }

    private func scheduleRender() {
        pendingWork?.cancel()
        pendingWork = scheduler.schedule(after: debounceInterval) { [weak self] in
            guard let self else { return }
            self.pendingWork = nil
            self.onRender?(self.text)
        }
    }
}
