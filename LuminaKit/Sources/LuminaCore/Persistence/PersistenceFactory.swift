import Foundation

// WP-8. Which store a launch gets. Replace the memory store with the file-backed one.

/// One store per directory per process, so two windows share it (R-72).
private let sharedStores = SharedStores()
private final class SharedStores: @unchecked Sendable {
    let lock = NSLock(); var stores: [String: any PersistenceStore] = [:]
}

public func makePersistence(config: LaunchConfig) -> any PersistenceStore {
    let key = config.storeDir?.path ?? "memory"
    return sharedStores.lock.withLock {
        if let s = sharedStores.stores[key] { return s }
        let s = MemoryPersistence(); sharedStores.stores[key] = s; return s
    }
}
