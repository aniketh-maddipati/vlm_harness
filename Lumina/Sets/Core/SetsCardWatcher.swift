import AppKit

/// Notices camera cards going in and out (ROADMAP "v1: card detection"). No polling: NSWorkspace
/// mount notifications. A Sony card is a volume with /DCIM/1xxMSDCF. Identified by volume UUID so
/// a re-inserted card resumes even when every card is called "Untitled".
///
/// In the App Sandbox (threat model T10, release task R1c) a volume's DCIM cannot be listed until
/// the user picked the card in a panel. So a mount is noticed from the volume's resource values
/// alone (name, UUID, removable), which the sandbox allows, and inspected only when it can be read:
/// - readable as it is (no sandbox, or a grant this process already holds): inspected as before;
/// - refused, and a grant kept for this card (`grant`, by volume UUID): the grant's access is
///   started and the card inspected, so the same card a second time needs no click;
/// - refused and no grant: an *unknown* card (`known == false`): its name and volume, no count,
///   no folders. "Cull this card" then asks for it in a panel (`SetsBridge.cullCard`).
/// A volume whose DCIM is simply not there (no sandbox) is not a card, as before.
@MainActor
final class SetsCardWatcher {
    struct Card: Equatable {
        let volume: URL
        let uuid: String
        let name: String
        /// Sony DCIM folders when present, otherwise every DCIM subfolder; empty while not known.
        let folders: [URL]
        /// True when the chosen folders contain at least one ARW or DNG.
        let sony: Bool
        /// Number of ARW and DNG files in the chosen folders.
        var arwCount: Int
        /// Total bytes of the ARW and DNG files counted by `arwCount`.
        var bytes: Int64
        /// False: noticed but not readable yet (sandbox, no grant): count, size, folders and
        /// whether it is a Sony card are not known.
        var known: Bool = true
        /// How it became readable: "open" (it was), "bookmark" (a grant kept from an earlier
        /// pick for "Cull this card"), "recent" (a recent shoot opened at the card's root or DCIM),
        /// "panel" (picked just now). Nil while not known.
        var grant: String? = "open"
    }

    /// Whether this process may list a folder now. `refused` is the sandbox's answer (EPERM);
    /// anything else that fails (nothing there, permission bits) is `missing`, as before the
    /// sandbox: not a card.
    enum Access: Equatable { case readable, missing, refused }

    var onChange: ((Card?, _ removed: Card?) -> Void)?
    /// A volume is about to go (Finder eject): let go of it now so the eject isn't refused as busy.
    var onWillUnmount: ((URL) -> Void)?
    /// Which volumes may count as cards. The app accepts all; the probe only its own test images,
    /// so a real card that happens to be mounted is never read by a test.
    var accepts: (URL) -> Bool = { _ in true }
    var onLog: ((String) -> Void)?
    /// A grant kept for this card (volume UUID): access started and held; the folder it covers.
    /// Nil when there is none or it cannot be used. The bridge answers from its card store.
    var grant: (_ uuid: String, _ volume: URL) -> String? = { _, _ in nil }
    /// The card's hold is to be let go (it went, or it turned out not to be a card).
    var release: (_ uuid: String) -> Void = { _ in }
    /// Injected for tests: the volume's UUID and name from its resource values, nil for a volume
    /// that is not card-like (the startup disk, a network share).
    var identify: (URL) -> (uuid: String, name: String)? = SetsCardWatcher.identify
    var access: (URL) -> Access = SetsCardWatcher.access
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
        for v in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey, .volumeNameKey], options: [.skipHiddenVolumes]) ?? [] {
            if accepts(v), let card = notice(v) { current = card; onChange?(card, nil); break }
        }
    }

    func stop() {
        tokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        tokens.removeAll()
    }

    func mounted(_ url: URL?) {
        guard let url, accepts(url) else { onLog?("mount \(url?.path ?? "?") accepted=false"); return }
        let card = notice(url)
        onLog?("mount \(url.path) accepted=true card=\(card.map { $0.known ? "known (\($0.grant ?? "?"))" : "unknown" } ?? "no")")
        guard let card else { return }
        if let old = current, old.uuid != card.uuid { release(old.uuid) }
        current = card
        onChange?(card, nil)
    }

    func unmounted(_ url: URL?) {
        guard let url, let cur = current, SetsIngest.plainPath(cur.volume) == SetsIngest.plainPath(url) else { return }
        current = nil
        release(cur.uuid)
        onChange?(nil, cur)
    }

    /// The card in the slot was granted just now (a panel's pick, held by the caller): inspected
    /// and announced again. False when it still cannot be read or is not a card after all.
    @discardableResult
    func granted(_ uuid: String) -> Bool {
        guard let cur = current, cur.uuid == uuid, var card = Self.inspect(cur.volume) else { return false }
        card = Card(volume: cur.volume, uuid: cur.uuid, name: cur.name, folders: card.folders, sony: card.sony, arwCount: card.arwCount, bytes: card.bytes, known: true, grant: "panel")
        current = card
        onLog?("card \(uuid) granted: \(card.arwCount) ARW")
        onChange?(card, nil)
        return true
    }

    /// What a mounted volume is, without reading it unless that is allowed.
    func notice(_ volume: URL) -> Card? {
        let dcim = volume.appendingPathComponent("DCIM")
        switch access(dcim) {
        case .readable:
            return Self.inspect(volume)
        case .missing:
            return nil
        case .refused:
            guard let id = identify(volume) else { return nil }
            if let how = grant(id.uuid, volume) {
                if let c = Self.inspect(volume) {
                    return Card(volume: volume, uuid: id.uuid, name: id.name, folders: c.folders, sony: c.sony, arwCount: c.arwCount, bytes: c.bytes, known: true, grant: how)
                }
                release(id.uuid)        // granted but not a card after all
                return nil
            }
            return Card(volume: volume, uuid: id.uuid, name: id.name, folders: [], sony: false, arwCount: 0, bytes: 0, known: false, grant: nil)
        }
    }

    /// The volume's UUID and name from its resource values (no read of its contents: the sandbox
    /// allows these for any mounted volume). Only local, removable or ejectable volumes that are
    /// not the startup disk can be cards.
    nonisolated static func identify(_ volume: URL) -> (uuid: String, name: String)? {
        let v = try? volume.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
                                                     .volumeIsRootFileSystemKey, .volumeIsLocalKey])
        guard v?.volumeIsRootFileSystem != true, v?.volumeIsLocal != false,
              v?.volumeIsRemovable == true || v?.volumeIsEjectable == true else { return nil }
        return (v?.volumeUUIDString ?? volume.path, v?.volumeName ?? volume.lastPathComponent)
    }

    nonisolated static func access(_ folder: URL) -> Access {
        let fd = open(folder.path, O_RDONLY | O_DIRECTORY)
        if fd >= 0 { close(fd); return .readable }
        switch errno {
        case EPERM: return .refused
        default: return .missing
        }
    }

    nonisolated static func inspect(_ volume: URL) -> Card? {
        let dcim = volume.appendingPathComponent("DCIM")
        guard let subs = try? FileManager.default.contentsOfDirectory(at: dcim, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return nil }
        let dirs = subs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !dirs.isEmpty else { return nil }
        let sonyDirs = dirs.filter { $0.lastPathComponent.range(of: #"^1\d\dMSDCF$"#, options: .regularExpression) != nil }
        let folders = sonyDirs.isEmpty ? dirs : sonyDirs
        let vals = try? volume.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey])
        var count = 0, bytes: Int64 = 0
        for d in folders {
            for f in (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
            where ["arw", "dng"].contains(f.pathExtension.lowercased()) {
                count += 1
                bytes += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return Card(volume: volume, uuid: vals?.volumeUUIDString ?? volume.path, name: vals?.volumeName ?? volume.lastPathComponent,
                    folders: folders, sony: count > 0, arwCount: count, bytes: bytes)
    }
}

/// The cards the user granted (R1c): one security-scoped bookmark per volume UUID, made from the
/// folder picked in "Cull this card"'s panel (the card's root or its DCIM), in `cards.json` next
/// to the shoot index. A card is the same card under any mount name, so its UUID is the key.
nonisolated struct SetsCardGrants {
    let file: URL

    init(supportDir: URL) { file = supportDir.appendingPathComponent("cards.json") }

    private struct Entry: Codable { var bookmark: Data; var path: String; var granted: Date }

    private func load() -> [String: Entry] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? dec.decode([String: Entry].self, from: data)) ?? [:]
    }

    func bookmark(_ uuid: String) -> Data? { load()[uuid]?.bookmark }

    func save(_ uuid: String, bookmark: Data, path: String) throws {
        var all = load()
        all[uuid] = Entry(bookmark: bookmark, path: path, granted: Date())
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SetsFileOps.replaceOwn(try enc.encode(all), at: file)
    }
}
