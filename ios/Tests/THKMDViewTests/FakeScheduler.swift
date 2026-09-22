import Foundation
@testable import THKMDView

/// A controllable stand-in for `DispatchQueueScheduler` so debounce behavior can be tested
/// deterministically, without real `asyncAfter` waits or `XCTestExpectation` sleeps.
final class FakeScheduler: DebounceScheduling {
    private final class Token: Cancellable {
        let work: () -> Void
        private(set) var isCancelled = false
        init(work: @escaping () -> Void) { self.work = work }
        func cancel() { isCancelled = true }
    }

    private var tokens: [Token] = []

    var scheduleCallCount: Int { tokens.count }

    func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> Cancellable {
        let token = Token(work: work)
        tokens.append(token)
        return token
    }

    /// Simulates the debounce interval fully elapsing: runs every token that hasn't been
    /// cancelled since it was scheduled (mirrors real DispatchWorkItem semantics, where a
    /// cancelled item never fires).
    func fireAll() {
        for token in tokens where !token.isCancelled {
            token.work()
        }
    }
}

/// A tiny seedable PRNG (SplitMix64) so chunk-boundary fuzzing is reproducible across runs.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
