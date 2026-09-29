import AppKit

/// Notices camera cards going in and out (ROADMAP "v1: card detection"). No polling: NSWorkspace
/// mount notifications. A Sony card is a volume with /DCIM/1xxMSDCF. Identified by volume UUID so
/// a re-inserted card resumes even when every card is called "Untitled".
@MainActor
final class SetsCardWatcher {
    struct Card: Equatable {
        let volume: URL
        let uuid: String
        let name: String
        let folders: [URL]          // DCIM/1xxMSDCF, oldest first
        let sony: Bool
        var arwCount: Int
        var bytes: Int64
    }

    var onChange: ((Card?, _ removed: Card?) -> Void)?
    /// A volume is about to go (Finder eject): let go of it now so the eject isn't refused as busy.
    var onWillUnmount: ((URL) -> Void)?
    /// Which volumes may count as cards. The app accepts all; the probe only its own test images,
    /// so a real card that happens to be mounted is never read by a test.
    var accepts: (URL) -> Bool = { _ in true }
    var onLog: ((String) -> Void)?
    private(set) var current: Card?
    private var tokens: [NSObjectProtocol] = []

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        tokens.append(nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] n in
            let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated { self?.mounted(url) }
        })
        tokens.append(nc.addObserver(forName: NSWorkspace.willUnmountNotification, object: nil, queue: .main) { [weak self] n in
            let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated { if let url, let self, self.accepts(url) { self.onWillUnmount?(url) } }
        })
        tokens.append(nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] n in
            let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated { self?.unmounted(url) }
        })
        // A card already in the slot at launch counts as inserted.
        for v in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [] {
            if accepts(v), let card = Self.inspect(v) { current = card; onChange?(card, nil); break }
        }
    }

    func stop() {
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens.removeAll()
    }

    private func mounted(_ url: URL?) {
        onLog?("mount \(url?.path ?? "?") accepted=\(url.map(accepts) ?? false) card=\(url.flatMap(Self.inspect) != nil)")
        guard let url, accepts(url), let card = Self.inspect(url) else { return }
        current = card
        onChange?(card, nil)
    }

    private func unmounted(_ url: URL?) {
        guard let url, let cur = current, SetsIngest.plainPath(cur.volume) == SetsIngest.plainPath(url) else { return }
        current = nil
        onChange?(nil, cur)
    }

    nonisolated static func inspect(_ volume: URL) -> Card? {
        let dcim = volume.appendingPathComponent("DCIM")
        guard let subs = try? FileManager.default.contentsOfDirectory(at: dcim, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return nil }
        let dirs = subs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !dirs.isEmpty else { return nil }
        let sonyDirs = dirs.filter { $0.lastPathComponent.range(of: #"^1\d\dMSDCF$"#, options: .regularExpression) != nil }
        let vals = try? volume.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey])
        var count = 0, bytes: Int64 = 0
        for d in sonyDirs {
            for f in (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
            where f.pathExtension.lowercased() == "arw" {
                count += 1
                bytes += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return Card(volume: volume, uuid: vals?.volumeUUIDString ?? volume.path, name: vals?.volumeName ?? volume.lastPathComponent,
                    folders: sonyDirs.isEmpty ? dirs : sonyDirs, sony: !sonyDirs.isEmpty, arwCount: count, bytes: bytes)
    }
}
