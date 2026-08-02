import AppKit
import Foundation

/// Watches mounted volumes and triggers zero-click ingest when a photo source appears.
@MainActor
final class IngestWatcher {
    static let shared = IngestWatcher()

    var onDiscover: ((IngestDiscovery) -> Void)?

    private var mountObserver: NSObjectProtocol?
    private var lastIngestedVolumePath: String?
    private var debounceTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard mountObserver == nil else { return }

        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor in self?.handleVolumeMounted(url) }
        }

        scanAlreadyMountedVolumes()
    }

    func stop() {
        if let mountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(mountObserver)
            self.mountObserver = nil
        }
        debounceTask?.cancel()
    }

    func scanAlreadyMountedVolumes() {
        for volume in IngestOrchestrator.mountedCandidateVolumes() {
            handleVolumeMounted(volume)
        }
    }

    private func handleVolumeMounted(_ volume: URL) {
        guard IngestPreferences.autoIngestOnMount else { return }
        guard IngestOrchestrator.shouldAutoIngest(volume: volume) else { return }

        let path = volume.path
        if lastIngestedVolumePath == path { return }

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            guard let root = IngestOrchestrator.bestIngestRoot(on: volume) else { return }
            let kind = SourceCatalog.classifyVolume(volume)
            guard let discovery = await IngestOrchestrator.discover(at: root, kind: kind) else { return }

            lastIngestedVolumePath = path
            onDiscover?(discovery)
        }
    }

    func resetLastVolume() {
        lastIngestedVolumePath = nil
    }
}

extension Notification.Name {
    static let luminaAutoIngest = Notification.Name("luminaAutoIngest")
}
