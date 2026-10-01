import Foundation

// WP-0 contract: time. Every guard, debounce and delayed apply reads the clock and schedules
// through the model's `Scheduler`, never `Date()` or `DispatchQueue.asyncAfter` directly, so the
// headless tests (trace replay) can run a whole flow on a virtual clock in milliseconds.

public final class ScheduledWork: @unchecked Sendable {
    fileprivate var block: (@MainActor () -> Void)?
    fileprivate let due: Date
    fileprivate init(due: Date, _ block: @escaping @MainActor () -> Void) { self.due = due; self.block = block }
    public func cancel() { block = nil }
    public var isCancelled: Bool { block == nil }
}

@MainActor
public protocol Scheduler: AnyObject {
    var now: Date { get }
    /// Run `block` on the main actor after `seconds`. Keep the token to cancel.
    @discardableResult func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) -> ScheduledWork
}

@MainActor
public final class LiveScheduler: Scheduler {
    public init() {}
    public var now: Date { Date() }
    @discardableResult public func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) -> ScheduledWork {
        let w = ScheduledWork(due: Date().addingTimeInterval(seconds), block)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { let b = w.block; w.block = nil; b?() } }
        return w
    }
}

/// A virtual clock for tests: nothing runs until `advance(_:)`.
@MainActor
public final class TestScheduler: Scheduler {
    public private(set) var now: Date
    private var queue: [ScheduledWork] = []
    public init(start: Date = Date(timeIntervalSince1970: 1_790_000_000)) { now = start }
    @discardableResult public func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) -> ScheduledWork {
        let w = ScheduledWork(due: now.addingTimeInterval(max(0, seconds)), block); queue.append(w); return w
    }
    /// Move time forward, running everything that falls due, in order (work scheduled by work included).
    public func advance(_ seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let i = queue.indices.filter({ queue[$0].due <= end }).min(by: { queue[$0].due < queue[$1].due }) {
            let w = queue.remove(at: i); now = max(now, w.due)
            let b = w.block; w.block = nil; b?()
        }
        now = end
    }
}
