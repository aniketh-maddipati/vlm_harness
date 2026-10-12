import Foundation

/// The drive a Skim shoot's clips are on (STORAGE.md step 3): its size, plain free space, the purgeable space
/// macOS can give back on its own (so the figure agrees with Finder, which counts it as available), whether it
/// is a camera card or read only (Skim moves nothing there), and the size of that drive's Trash when it can be
/// read. Read only: nothing here writes, moves or empties anything.
nonisolated struct SkimDrive: Sendable {
    struct Reading: Equatable, Sendable {
        var name: String
        var total: Int64?
        var free: Int64?
        var purgeable: Int64?
        var readOnly: Bool
        var card: Bool
        /// Why Skim will not move anything off this drive, in plain words; nil when it may.
        var refusal: String?
        /// Bytes in this drive's Trash; nil when the Trash cannot be read from here (not guessed).
        var trash: Int64?

        var json: [String: Any] {
            var o: [String: Any] = ["name": name, "readOnly": readOnly, "card": card]
            if let total { o["total"] = total }
            if let free { o["free"] = free }
            if let purgeable { o["purgeable"] = purgeable }
            if let refusal { o["refusal"] = refusal }
            if let trash { o["trash"] = trash }
            return o
        }
    }

    /// The plain words for a drive Skim must not move clips off. A card first: that is what he would recognise.
    static func refusal(path: String, readOnly: Bool, card: Bool) -> String? {
        let p = path.uppercased()
        if card || p.contains("/PRIVATE/M4ROOT") || p.hasSuffix("/PRIVATE/M4ROOT") {
            return "These clips are on a camera card. Skim never moves or deletes anything on a card; copy them to a drive first."
        }
        if readOnly { return "This drive is read only. Skim can't move anything off it." }
        return nil
    }

    /// Purgeable space: what "available for important use" adds to plain free space. Never negative.
    static func purgeable(free: Int64?, important: Int64?) -> Int64? {
        guard let free, let important, important > 0 else { return nil }
        return max(0, important - free)
    }

    /// The Trash folder macOS keeps for this user on a volume: the home folder's `.Trash` on the startup volume,
    /// `<volume>/.Trashes/<uid>` elsewhere.
    static func trashFolder(volume: URL, home: URL, uid: UInt32) -> URL {
        volume.path == "/" ? home.appendingPathComponent(".Trash", isDirectory: true)
                           : volume.appendingPathComponent(".Trashes", isDirectory: true).appendingPathComponent(String(uid), isDirectory: true)
    }

    /// Bytes under a folder, files only, symlinks not followed; nil when the folder can't be listed (the sandbox
    /// refuses the Trash unless the user has granted it). Stops at `limit` entries so a huge Trash can't hold the reply.
    static func bytes(under folder: URL, limit: Int = 200_000) -> Int64? {
        let fm = FileManager.default
        guard (try? fm.contentsOfDirectory(atPath: folder.path)) != nil,
              let en = fm.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey], options: [], errorHandler: { _, _ in true }) else { return nil }
        var tot: Int64 = 0, n = 0
        for case let u as URL in en {
            n += 1; if n > limit { break }
            guard let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]), v.isRegularFile == true else { continue }
            tot += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
        }
        return tot
    }

    /// The reading for the folder a shoot was opened from.
    static func read(folder: URL, home: URL, uid: UInt32) -> Reading {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeIsReadOnlyKey, .volumeURLKey]
        let v = try? folder.resourceValues(forKeys: keys)
        let free = v?.volumeAvailableCapacity.map(Int64.init), card = SetsFileOps.isCard(folder), ro = v?.volumeIsReadOnly ?? false
        let volume = v?.volume ?? URL(fileURLWithPath: "/")
        return Reading(name: v?.volumeName ?? volume.lastPathComponent, total: v?.volumeTotalCapacity.map(Int64.init), free: free,
                       purgeable: purgeable(free: free, important: v?.volumeAvailableCapacityForImportantUsage),
                       readOnly: ro, card: card, refusal: refusal(path: folder.path, readOnly: ro, card: card),
                       trash: bytes(under: trashFolder(volume: volume, home: home, uid: uid)))
    }

    /// The user's real home folder (in the sandbox, NSHomeDirectory is the container).
    static func realHome() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir), isDirectory: true) }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}
