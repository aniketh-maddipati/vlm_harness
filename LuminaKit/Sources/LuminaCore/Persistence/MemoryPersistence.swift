import Foundation

// WP-8. The in-memory store (tests, the snapshot tool). The file-backed store lives next to it.

public final class MemoryPersistence: PersistenceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var byKey: [String: Snapshot] = [:], last: String?
    private var observers: [@Sendable (Snapshot) -> Void] = []
    public init() {}
    public func loadLast() throws -> Snapshot? { lock.withLock { last.flatMap { byKey[$0] } } }
    public func load(shootKey: String) throws -> Snapshot? { lock.withLock { byKey[shootKey] } }
    public func save(_ snapshot: Snapshot) throws {
        if Faults.shared.has(.storageFull) { throw PersistenceError.storageFull }
        let obs: [@Sendable (Snapshot) -> Void] = lock.withLock { byKey[snapshot.shootKey] = snapshot; last = snapshot.shootKey; return observers }
        obs.forEach { $0(snapshot) }
    }
    public func clear(shootKey: String) throws { lock.withLock { byKey[shootKey] = nil; if last == shootKey { last = nil } } }
    public func observe(_ onChange: @escaping @Sendable (Snapshot) -> Void) { lock.withLock { observers.append(onChange) } }
}
