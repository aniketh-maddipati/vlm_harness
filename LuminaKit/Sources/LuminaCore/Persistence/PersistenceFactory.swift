import Foundation

// WP-8. Which store a launch gets.

/// One store per directory per process, so two windows share it (R-72).
private let sharedStores = SharedStores()
private final class SharedStores: @unchecked Sendable {
    let lock = NSLock(); var stores: [String: any PersistenceStore] = [:]
}

/// `LUMINA_STORE_DIR` → files in that directory and nowhere else. Otherwise files in
/// `~/Library/Application Support/Lumina/native/`, except where the user's real store must not
/// be touched: `LUMINA_STORE=memory`, a UI-test launch without a store directory, and any
/// process running XCTest get a memory store (a fresh one per call under XCTest, so tests that
/// don't pass a store don't share state).
public func makePersistence(config: LaunchConfig) -> any PersistenceStore {
    if let dir = config.storeDir { return shared(dir.standardizedFileURL.path) { FilePersistence(directory: dir) } }
    if PersistenceEnvironment.underXCTest { return MemoryPersistence() }
    if config.uiTest || ProcessInfo.processInfo.environment["LUMINA_STORE"] == "memory" { return shared("memory") { MemoryPersistence() } }
    let dir = FilePersistence.defaultDirectory
    return shared(dir.path) { FilePersistence(directory: dir) }
}

private func shared(_ key: String, _ make: () -> any PersistenceStore) -> any PersistenceStore {
    sharedStores.lock.withLock {
        if let s = sharedStores.stores[key] { return s }
        let s = make(); sharedStores.stores[key] = s; return s
    }
}

enum PersistenceEnvironment {
    static let underXCTest = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
