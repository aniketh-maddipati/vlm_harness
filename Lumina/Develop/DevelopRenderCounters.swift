import Foundation

/// Process-wide develop counters. Instrumentation only — not a store, scheduler, or cache.
nonisolated enum DevelopRenderCounters {
    struct Snapshot: Equatable, Sendable {
        var preparedSessionCreated = 0
        var preparedSessionHits = 0
        var interactiveMaterializations = 0
        var graphRenders = 0
        var gpuUploads = 0
        var variantRenders = 0
        var metalPresents = 0
        var cancellations = 0
    }

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var value = Snapshot()
    }

    private static let storage = Storage()

    static func reset() {
        storage.lock.lock()
        storage.value = Snapshot()
        storage.lock.unlock()
    }

    static func snapshot() -> Snapshot {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.value
    }

    static func recordPreparedSessionCreated() { add(\.preparedSessionCreated) }
    static func recordPreparedSessionHit() { add(\.preparedSessionHits) }
    static func recordInteractiveMaterialization() { add(\.interactiveMaterializations) }
    static func recordGraphRender() { add(\.graphRenders) }
    static func recordGPUUpload() { add(\.gpuUploads) }
    static func recordVariantRender() { add(\.variantRenders) }
    static func recordMetalPresent() { add(\.metalPresents) }
    static func recordCancellation() { add(\.cancellations) }

    private static func add(_ keyPath: WritableKeyPath<Snapshot, Int>, by amount: Int = 1) {
        storage.lock.lock()
        storage.value[keyPath: keyPath] += amount
        storage.lock.unlock()
    }
}
