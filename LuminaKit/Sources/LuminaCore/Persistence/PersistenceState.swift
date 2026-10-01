import Foundation

// WP-8. One window's persistence bookkeeping: what is waiting to be written, what was written
// last, and why the warning line says what it says. Reached with `model.persistence`.

@MainActor
final class PersistenceState {
    typealias Item = (snapshot: Snapshot, extras: SnapshotExtras)

    /// At most one write per interval while changes keep coming (a slider drag, 5,000 fast
    /// decisions); a change after a quiet interval is written at once. The prototype's 250 ms.
    static let interval: TimeInterval = 0.25
    /// While the last write failed, try again this often even if nothing changes.
    static let retryInterval: TimeInterval = 5
    /// Copy progress is written at least this often (R-1A).
    static let copyStride = 15

    /// The observer, the registry and the quit hook are in place.
    var wired = false
    /// The newest state not yet handed to the store.
    var pending: Item?
    var timer: ScheduledWork?
    var retry: ScheduledWork?
    var lastWriteAt = Date.distantPast
    /// What the store was last given (or what was restored from it).
    var written: Item?
    /// Writes handed to the background queue and not yet reported back.
    var inFlight = 0
    /// Each write has a number; a result older than the newest one handled is ignored.
    var seq = 0, handled = 0
    /// The last write didn't land: the warning shows, and the next change, the retry timer or a flush tries again.
    var failed = false
    var otherWindow = false
    var reportedWriteError = false
    /// Write attempts so far (tests).
    var writes = 0

    /// Encode and write off the main thread. On for the real clock; tests on the virtual clock
    /// write in place so a flow stays deterministic.
    var background: Bool
    let queue = DispatchQueue(label: "com.lumina.persistence", qos: .userInitiated)

    /// The imported folder of the shoot on screen (R-19), stashed by WP-2.
    var folderPath: String?
    var folderBookmark: Data?
    /// The last session's folder, when it isn't the shoot on screen.
    var reopen: Snapshot?

    init(background: Bool) { self.background = background }

    nonisolated static func save(_ item: Item, to store: any PersistenceStore) -> Error? {
        do {
            if let s = store as? any SnapshotExtrasStore { try s.save(item.snapshot, extras: item.extras) } else { try store.save(item.snapshot) }
            return nil
        } catch { return error }
    }

    /// The same state, whoever wrote it and whenever.
    static func same(_ a: Item, _ b: Item) -> Bool {
        var x = a.snapshot, y = b.snapshot
        x.revision = 0; y.revision = 0; x.writer = ""; y.writer = ""
        return a.extras == b.extras && x == y
    }
}

/// Every window's model, so quitting can flush them all.
@MainActor
enum PersistenceRegistry {
    private struct Weak { weak var model: AppModel? }
    private static var models: [Weak] = []
    private static var quitHook: NSObjectProtocol?

    static func add(_ m: AppModel) {
        models.removeAll { $0.model == nil }
        models.append(Weak(model: m))
        // AppKit posts this on the main thread on the way out. By name, so Core stays free of AppKit.
        if quitHook == nil {
            quitHook = NotificationCenter.default.addObserver(forName: Notification.Name("NSApplicationWillTerminateNotification"), object: nil, queue: nil) { _ in
                if Thread.isMainThread { MainActor.assumeIsolated { PersistenceRegistry.flushAll() } }
            }
        }
    }

    static func flushAll() { for w in models { w.model?.flushPersistence() } }
}
