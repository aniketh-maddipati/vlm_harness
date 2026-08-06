import Foundation

/// Atomic identity for one live editing surface.
///
/// A render may publish only when every field still matches the editor's
/// current identity. Stale results from a previous photo or prepared session
/// are discarded and never replace the displayed texture.
struct DevelopEditorIdentity: Equatable, Sendable, Hashable {
    let photoID: UUID
    let preparedSessionID: UUID
}

/// Fields every render request and result must carry for publication gating.
struct DevelopRenderIdentity: Equatable, Sendable, Hashable {
    let photoID: UUID
    let preparedSessionID: UUID
    let recipeRevision: UInt64
    let requestID: UUID
    let quality: DevelopRenderQuality
    let displayProfileID: String
}

/// Debug lifecycle counters — prove slider scrub does not reconstruct ownership.
struct DevelopLifecycleCounters: Equatable, Sendable {
    var editorModelInits: Int = 0
    var sessionPrepares: Int = 0
    var metalViewMakes: Int = 0
    var metalCoordinatorInits: Int = 0
    var mtkViewMakes: Int = 0
    var interactiveFilterApplies: Int = 0

    var summaryLine: String {
        "life editor=\(editorModelInits) session=\(sessionPrepares) metalView=\(metalViewMakes) "
            + "coord=\(metalCoordinatorInits) mtk=\(mtkViewMakes) filterApply=\(interactiveFilterApplies)"
    }
}

/// Structured live-edit path logger (temporary instrumentation for this phase).
enum DevelopLiveLog {
    static var enabled: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.environment["LUMINA_LIVE_EDIT_LOG"] == "1"
        #endif
    }

    private static let fileLock = NSLock()
    private static var logFileURL: URL? = {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("artifacts/live-edit-v1", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("live-edit-path.log")
    }()

    static func event(_ message: String) {
        guard enabled else { return }
        let ts = String(format: "%.3f", CFAbsoluteTimeGetCurrent())
        let line = "[live-edit \(ts)] \(message)\n"
        fputs(line, stderr)
        fflush(stderr)
        fileLock.lock()
        defer { fileLock.unlock() }
        if let url = logFileURL, let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
}
