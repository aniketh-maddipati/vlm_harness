import Foundation

/// Watches a user-granted Downloads folder for complete AirDrop RAWs without opening or changing
/// any file. The state machine is separate so the one-second stability rule is deterministic in
/// tests and cannot be bypassed by a filesystem notification.
nonisolated final class SetsDownloadsWatcher: @unchecked Sendable {
    struct Entry: Equatable, Sendable {
        let name: String
        let size: Int64
        let isDirectory: Bool
    }

    struct Arrival: Equatable, Sendable {
        let name: String
        let size: Int64
    }

    struct Batch: Equatable, Sendable {
        let raws: [Arrival]
        let lossy: Int

        var isEmpty: Bool { raws.isEmpty && lossy == 0 }
    }

    /// Foundation-only scan state. A name stays reported until it disappears; reappearing after
    /// that is a new arrival, while a file present in the baseline remains ignored for its lifetime.
    struct Core: Sendable {
        private struct Observation: Sendable {
            var size: Int64
            var stableSince: TimeInterval
            var reported: Bool
        }

        let stabilityInterval: TimeInterval
        private var observations: [String: Observation] = [:]
        private var hasBaseline = false

        init(stabilityInterval: TimeInterval = 1.0) {
            self.stabilityInterval = max(0, stabilityInterval)
        }

        mutating func scan(entries: [Entry], now: TimeInterval) -> Batch {
            let blockers = Set(entries.map(\.name))
            let candidates = entries.filter {
                !$0.isDirectory && Self.kind(of: $0.name) != nil && !Self.isIgnoredName($0.name)
            }
            let present = Set(candidates.map(\.name))
            observations = observations.filter { present.contains($0.key) }

            if !hasBaseline {
                hasBaseline = true
                for entry in candidates {
                    observations[entry.name] = Observation(size: entry.size, stableSince: now, reported: true)
                }
                return Batch(raws: [], lossy: 0)
            }

            var raws: [Arrival] = []
            var lossy = 0
            for entry in candidates {
                let kind = Self.kind(of: entry.name)!
                var observation = observations[entry.name]
                    ?? Observation(size: entry.size, stableSince: now, reported: false)

                if observation.size != entry.size {
                    observation.size = entry.size
                    observation.stableSince = now
                }

                let hasDownloadSibling = blockers.contains(entry.name + ".download")
                if !observation.reported,
                   entry.size > 0,
                   now - observation.stableSince >= stabilityInterval,
                   !hasDownloadSibling {
                    observation.reported = true
                    switch kind {
                    case .raw:
                        raws.append(Arrival(name: entry.name, size: entry.size))
                    case .lossy:
                        lossy += 1
                    }
                }
                observations[entry.name] = observation
            }
            return Batch(raws: raws, lossy: lossy)
        }

        private enum Kind { case raw, lossy }

        private static func kind(of name: String) -> Kind? {
            switch (name as NSString).pathExtension.lowercased() {
            case "dng", "arw": return .raw
            case "heic", "heif", "jpg", "jpeg": return .lossy
            default: return nil
            }
        }

        private static func isIgnoredName(_ name: String) -> Bool {
            let lower = name.lowercased()
            return name.hasPrefix(".")
                || lower.hasSuffix(".download")
                || lower.hasSuffix(".crdownload")
                || lower.hasSuffix(".part")
        }
    }

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let stabilityInterval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var folder: URL?
    private var core: Core?
    private var onBatch: ((Batch) -> Void)?
    private var generation: UInt64 = 0

    init(stabilityInterval: TimeInterval = 1.0) {
        self.stabilityInterval = stabilityInterval
        queue = DispatchQueue(label: "lumina.downloads-watch", qos: .utility)
        queue.setSpecific(key: queueKey, value: 1)
    }

    /// Starts with an immediate baseline scan, then polls at `every`. Re-starting replaces the
    /// previous watch. Batches are serialized on the watcher's utility queue.
    func start(folder: URL, every: TimeInterval = 1.5, onBatch: @escaping (Batch) -> Void) {
        onQueue {
            cancelTimer()
            generation &+= 1
            self.folder = folder
            core = Core(stabilityInterval: stabilityInterval)
            self.onBatch = onBatch

            let token = generation
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: max(0.01, every))
            source.setEventHandler { [weak self] in
                guard let self, generation == token else { return }
                scan()
            }
            timer = source
            source.resume()
        }
    }

    /// Cancels synchronously. Once this returns no listing or batch callback from this watch can
    /// begin. It is safe to call repeatedly, including from inside `onBatch`.
    func stop() {
        onQueue {
            generation &+= 1
            cancelTimer()
            folder = nil
            core = nil
            onBatch = nil
        }
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }

    private func scan() {
        guard let folder, var core, let entries = Self.list(folder) else { return }
        let batch = core.scan(entries: entries, now: ProcessInfo.processInfo.systemUptime)
        self.core = core
        if !batch.isEmpty { onBatch?(batch) }
    }

    /// A failed listing is not an empty folder: retaining the previous scan avoids reporting every
    /// file as newly arrived after a transient sandbox or filesystem error.
    private static func list(_ folder: URL) -> [Entry]? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return nil }
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            return Entry(
                name: url.lastPathComponent,
                size: Int64(values?.fileSize ?? 0),
                isDirectory: values?.isDirectory == true
            )
        }.sorted { $0.name < $1.name }
    }

    private func cancelTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func onQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return body()
        }
        return queue.sync(execute: body)
    }
}
