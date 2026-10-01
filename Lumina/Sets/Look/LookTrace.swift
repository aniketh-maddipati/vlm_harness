import Foundation
import QuartzCore

/// A small ring of timestamped events on the canvas clock (`CACurrentMediaTime`, ms): dropped
/// display-link ticks, base builds, prefetch, rest statistics, region tiles. The probe reads it
/// (`lumina.edit.stats().trace`) to tie a dropped frame to what ran at the same time.
nonisolated enum LookTrace {
    struct Event: Codable, Equatable, Sendable {
        var t: Double
        var what: String
        var ms: Double?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var ring: [Event] = []
    static let capacity = 600

    static func now() -> Double { CACurrentMediaTime() * 1000 }

    static func mark(_ what: String, ms: Double? = nil, at t: Double = now()) {
        lock.withLock {
            ring.append(Event(t: (t * 10).rounded() / 10, what: what, ms: ms.map { ($0 * 10).rounded() / 10 }))
            if ring.count > capacity { ring.removeFirst(ring.count - capacity) }
        }
    }

    /// Times `body` and records it when done (`what` with its duration).
    @discardableResult
    static func span<T>(_ what: String, _ body: () throws -> T) rethrows -> T {
        let t0 = now()
        defer { mark(what, ms: now() - t0, at: t0) }
        return try body()
    }

    static var events: [Event] { lock.withLock { ring } }
}
