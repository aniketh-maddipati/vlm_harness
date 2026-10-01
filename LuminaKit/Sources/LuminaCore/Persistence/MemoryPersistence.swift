import Foundation

// WP-8. The in-memory store (tests, the snapshot tool). The file-backed store lives next to it.

public final class MemoryPersistence: PersistenceStore, SnapshotExtrasStore, @unchecked Sendable {
    private let lock = NSLock()
    private var byKey: [String: Snapshot] = [:], extrasByKey: [String: SnapshotExtras] = [:], last: String?
    private var observers: [@Sendable (Snapshot) -> Void] = []
    private var _writes = 0
    public init() {}
    /// Saves so far (the coalescing tests count them).
    public var writeCount: Int { lock.withLock { _writes } }
    public func loadLast() throws -> Snapshot? { lock.withLock { last.flatMap { byKey[$0] } } }
    public func load(shootKey: String) throws -> Snapshot? { lock.withLock { byKey[shootKey] } }
    public func loadWithExtras(shootKey: String) throws -> (snapshot: Snapshot, extras: SnapshotExtras)? {
        lock.withLock { byKey[shootKey].map { ($0, extrasByKey[shootKey] ?? SnapshotExtras()) } }
    }
    public func save(_ snapshot: Snapshot) throws { try store(snapshot, nil) }
    public func save(_ snapshot: Snapshot, extras: SnapshotExtras) throws { try store(snapshot, extras) }
    private func store(_ snapshot: Snapshot, _ extras: SnapshotExtras?) throws {
        if Faults.shared.has(.storageFull) { throw PersistenceError.storageFull }
        let obs: [@Sendable (Snapshot) -> Void] = lock.withLock {
            byKey[snapshot.shootKey] = snapshot; last = snapshot.shootKey; _writes += 1
            if let extras { extrasByKey[snapshot.shootKey] = extras }
            return observers
        }
        obs.forEach { $0(snapshot) }
    }
    public func clear(shootKey: String) throws {
        lock.withLock { byKey[shootKey] = nil; extrasByKey[shootKey] = nil; if last == shootKey { last = nil } }
    }
    public func observe(_ onChange: @escaping @Sendable (Snapshot) -> Void) { lock.withLock { observers.append(onChange) } }
}
