import Foundation

/// Lumina Ingest (the Debug prototype, `LUMINA_PAGE=ingest`): what the page read is copied into one library
/// folder the owner picks once. Foundation only (tested on Linux too).
///
/// - Copies never move and never write to the source: every file goes through `SetsFileOps.copyVerifiedHashed`
///   (SHA-256 of the original, streamed copy hashed again, the copy re-read before it gets its name; a name
///   clash with other bytes gets a numbered name, identical bytes are already done).
/// - A photo or clip travels with its companions: the files beside it with the same stem (`DSC01234.JPG` of a
///   RAW + JPEG pair, `.xmp`, Sony's `C0001M01.XML`, `.THM`, …), into the same folder, renamed with it.
/// - The library keeps its identities (`IngestLibrary`, JSON in the container): the page's key (size + crc32
///   of the first and last 64 KB) → where the copy is and its SHA-256. "Already here" is a key that is in it;
///   the copy step still hashes the original against the copy kept, so a key that matched by chance is copied.
nonisolated enum IngestCopy {
    /// Extensions that go with a photo or clip of the same stem.
    static let companionExts: Set<String> = ["xmp", "xml", "thm", "bim", "cpi", "mpl", "bdm", "smi", "lrv", "aae", "srt",
                                             "jpg", "jpeg", "arw", "dng", "cr2", "cr3", "nef", "raf", "orf", "rw2", "heic", "heif", "hif"]

    struct Item: Equatable, Sendable {
        /// The page's identity key; empty for a file the page did not read (copied, never remembered).
        var key: String
        /// The file itself (the RAW of a RAW + JPEG pair).
        var source: URL
        /// The folder the owner chose that holds it (a card's root, a folder): nothing is written inside it.
        var root: URL
        /// The library sub-folder: "2026-10-28", "No date", or "Other/<source>/<sub>".
        var folder: String
    }

    struct Result: Equatable, Sendable {
        var key: String
        var ok: Bool
        var why: String?
        /// Files written or found identical (main file + companions).
        var files = 0
        var bytes: Int64 = 0
        /// Every file was already in the library with the same bytes; nothing new was written.
        var already = false
        /// Where the main file is in the library ("2026-10-28/DSC01234.ARW").
        var rel: String?
        /// The source files that now have a verified copy (the main file and its companions): what "safe to format"
        /// is checked against (`unaccounted`).
        var sources: [String] = []
    }

    /// Why a copy stopped because the library's disk went away (unplugged, unmounted): the queue stops on it.
    static let destinationGone = "destination gone"

    /// The files beside `url` that go with it: same stem (any case), then `.ext` or Sony's `M01.ext`, and an
    /// extension in `companionExts`. Not `url` itself, never a folder or a dot-file.
    static func companions(of url: URL) -> [URL] {
        let dir = url.deletingLastPathComponent(), name = url.lastPathComponent
        let stem = (name as NSString).deletingPathExtension.lowercased()
        guard !stem.isEmpty, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.sorted().compactMap { n in
            guard n != name, !n.hasPrefix("."), companionExts.contains((n as NSString).pathExtension.lowercased()) else { return nil }
            let s = (n as NSString).deletingPathExtension.lowercased()
            guard s == stem || (s.hasPrefix(stem) && s.dropFirst(stem.count).range(of: #"^m\d\d$"#, options: .regularExpression) != nil) else { return nil }
            let u = dir.appendingPathComponent(n)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
            return u
        }
    }

    /// A library sub-folder name the page sent, made safe: no `..`, no leading `/`, no empty parts.
    static func safeFolder(_ folder: String) -> String? {
        let parts = folder.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." || $0.hasPrefix(".") }) else { return nil }
        return parts.joined(separator: "/")
    }

    /// Copies one item and its companions into `library`, verified. Never writes to the source.
    static func copy(_ item: Item, into library: URL, store: IngestLibrary) -> Result {
        var r = Result(key: item.key, ok: false)
        let fm = FileManager.default
        if let no = SetsFileOps.refusal(destination: library, sources: [item.root]) { r.why = no.hasPrefix("Pick a folder that isn't on the card") ? "library on the card" : "library inside the source"; return r }
        // A library whose disk went away fails at once, before the original is read in full.
        var libIsDir: ObjCBool = false
        guard fm.fileExists(atPath: library.path, isDirectory: &libIsDir), libIsDir.boolValue else { r.why = destinationGone; return r }
        guard let folder = safeFolder(item.folder) else { r.why = "refused"; return r }
        if (try? fm.attributesOfItem(atPath: item.source.path))?[.type] as? FileAttributeType == .typeSymbolicLink { r.why = "a link, not copied"; return r }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: item.source.path, isDirectory: &isDir) else { r.why = "missing"; return r }
        // A folder macOS shows as one file (a Final Cut library, a Photos library): copied whole, as it is.
        if isDir.boolValue { return copyPackage(item, folder: folder, library: library, lib: library.standardizedFileURL) }
        // The file the page read, not another one that answers to the same path (two chosen folders of one name)
        // or one that changed since.
        if !item.key.isEmpty, pageKey(item.source) != item.key { r.why = "not the file that was read"; return r }
        let lib = library.standardizedFileURL
        var dst = lib.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(item.source.lastPathComponent)
        // Already here: the copy kept for this key, if its bytes are the original's.
        if !item.key.isEmpty, let e = store.entry(item.key) {
            let kept = lib.appendingPathComponent(e.rel)
            if fm.fileExists(atPath: kept.path) { dst = kept }
        }
        var newBytes = false
        do {
            let (out, sha) = try SetsFileOps.copyVerifiedHashed(item.source, to: dst)
            let target: URL
            var numbered = false
            switch out {
            case .alreadyThere(let u): target = u
            case .copied(let u): target = u; newBytes = true
            case .renamed(let u): target = u; newBytes = true; numbered = true
            }
            r.files = 1
            r.sources = [item.source.standardizedFileURL.path]
            r.bytes = Int64((try? item.source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            r.rel = String(target.standardizedFileURL.path.dropFirst(lib.path.count + 1))
            // Companions keep their own names beside the copy; a main file numbered for a name clash numbers them
            // too, so the pair stays a pair. (Bytes already kept under another name don't rename them: DSC00300.JPG
            // stays DSC00300.JPG beside an identical DSC00200.ARW.)
            let srcStem = (item.source.lastPathComponent as NSString).deletingPathExtension
            let dstStem = numbered ? (target.lastPathComponent as NSString).deletingPathExtension : srcStem
            for c in companions(of: item.source) {
                let rest = String(c.lastPathComponent.dropFirst(srcStem.count))
                let cd = target.deletingLastPathComponent().appendingPathComponent(dstStem + rest)
                switch try SetsFileOps.copyVerified(c, to: cd) {
                case .alreadyThere: break
                case .copied, .renamed: newBytes = true
                }
                r.files += 1
                r.sources.append(c.standardizedFileURL.path)
                r.bytes += Int64((try? c.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            if !item.key.isEmpty, let rel = r.rel { store.record(item.key, IngestLibrary.Entry(rel: rel, sha: sha, size: r.bytes)) }
            r.ok = true
            r.already = !newBytes
        } catch where !fm.fileExists(atPath: library.path) {
            r.why = destinationGone
        } catch let e as SetsFileOps.Failure {
            r.why = e.description.contains("doesn't match") ? "copy doesn't match" : e.description.contains("changed while") ? "changed while copying" : "failed"
        } catch {
            r.why = SetsFileOps.reason(error)
        }
        return r
    }
}

/// The library's identities, kept natively in the container (`ingest/library.json`): which folder is the library
/// (a security-scoped bookmark, picked once) and key → where its copy is, the copy's SHA-256 and size.
nonisolated final class IngestLibrary: @unchecked Sendable {
    struct Entry: Codable, Equatable, Sendable { var rel: String; var sha: String; var size: Int64 }
    /// A folder or card the owner chose before (`IngestHost`): shown as a source so it opens without the panel.
    /// `volume` is a card's volume UUID (the card is offered only while it is in); nil for a folder.
    struct Place: Codable, Equatable, Sendable { var path: String; var name: String; var bookmark: Data; var volume: String? }
    static let maxPlaces = 8
    private struct File: Codable { var path: String?; var bookmark: Data?; var keys: [String: Entry] = [:]; var places: [Place]?; var pattern: String? }

    let url: URL
    private let lock = NSLock()
    private var file: File

    init(url: URL) {
        self.url = url
        file = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(File.self, from: $0) } ?? File()
    }

    var path: String? { lock.withLock { file.path } }
    var bookmark: Data? { lock.withLock { file.bookmark } }
    var count: Int { lock.withLock { file.keys.count } }
    var keys: [String] { lock.withLock { Array(file.keys.keys) } }
    func entry(_ key: String) -> Entry? { lock.withLock { file.keys[key] } }
    func has(_ keys: [String]) -> [String] { lock.withLock { keys.filter { file.keys[$0] != nil } } }

    func record(_ key: String, _ e: Entry) { lock.withLock { file.keys[key] = e } }

    /// A new library folder. The identities stay only if it is the same folder.
    func setFolder(_ path: String, bookmark: Data?) {
        lock.withLock {
            if file.path != path { file.keys = [:] }
            file.path = path; file.bookmark = bookmark
        }
    }

    var places: [Place] { lock.withLock { file.places ?? [] } }

    /// The owner's folder pattern ("{year}/{start} {shoot}/{kind}"), kept as typed; nil: plain dated folders. The
    /// page turns it into folders (lumina-ingest-shoots.js); each one still goes through `IngestCopy.safeFolder`.
    /// It stays when another library folder is picked: it is the owner's way of filing, not that folder's.
    var pattern: String? { lock.withLock { file.pattern } }
    static let maxPattern = 200
    func setPattern(_ p: String?) {
        let t = (p ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock { file.pattern = t.isEmpty ? nil : String(t.prefix(Self.maxPattern)) }
    }

    /// Remembers a chosen folder or card, newest first; one entry per folder (per card: per volume), at most
    /// `maxPlaces`.
    func remember(_ p: Place) {
        lock.withLock {
            var all = (file.places ?? []).filter { $0.path != p.path && (p.volume == nil || $0.volume != p.volume) }
            all.insert(p, at: 0)
            file.places = Array(all.prefix(Self.maxPlaces))
        }
    }

    /// Forgets the remembered folders (the page's "Forget these"); cards keep their grant.
    func forgetFolders() { lock.withLock { file.places = (file.places ?? []).filter { $0.volume != nil } } }

    /// Forgets the identities (the page's Forget); the library's files are not touched.
    func forget() { lock.withLock { file.keys = [:] } }

    func save() throws {
        let data = try lock.withLock { try JSONEncoder().encode(file) }
        try SetsFileOps.replaceOwn(data, at: url)
    }
}

nonisolated extension IngestCopy {
    /// Whether `url` is the root of its volume (a whole card chosen, not one of its folders).
    static func isVolumeRoot(_ url: URL) -> Bool {
        guard let v = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume else { return false }
        return v.standardizedFileURL.resolvingSymlinksInPath().path == url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Where the page's file is on disk. The page knows a file as its `webkitRelativePath` ("SONY/DCIM/100MSDCF/
    /// DSC01234.ARW": the chosen folder's name first) or, for files chosen on their own, its name. Only inside a
    /// folder or file the owner chose in Ingest's open panel (`roots`); no `..`, no leading `/`.
    static func resolve(_ path: String, roots: [URL]) -> (file: URL, root: URL)? { resolveAll(path, roots: roots).first }

    /// Every chosen folder or file the page's path can name, newest choice first. Two chosen folders with one name
    /// (two cards' `100MSDCF`) both answer; the copy takes the one whose bytes are the page's key.
    static func resolveAll(_ path: String, roots: [URL]) -> [(file: URL, root: URL)] {
        var out: [(file: URL, root: URL)] = []
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.hasPrefix("/"), !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { return [] }
        let fm = FileManager.default
        for root in roots.reversed() {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard parts[0] == root.lastPathComponent else { continue }
                // the chosen folder itself: a package that was dropped as it is
                if parts.count == 1 {
                    if !out.contains(where: { $0.file.standardizedFileURL.path == root.standardizedFileURL.path }) { out.append((root, root)) }
                    continue
                }
                let f = root.appendingPathComponent(parts.dropFirst().joined(separator: "/"))
                let rp = root.standardizedFileURL.resolvingSymlinksInPath().path, fp = f.standardizedFileURL.resolvingSymlinksInPath().path
                guard fp.hasPrefix(rp + "/"), fm.fileExists(atPath: f.path) || (try? fm.attributesOfItem(atPath: f.path)) != nil else { continue }
                if !out.contains(where: { $0.file.standardizedFileURL.path == f.standardizedFileURL.path }) { out.append((f, root)) }
            } else if parts.count == 1, root.lastPathComponent == parts[0] {
                if !out.contains(where: { $0.file.standardizedFileURL.path == root.standardizedFileURL.path }) { out.append((root, root.deletingLastPathComponent())) }
            }
        }
        return out
    }

    /// The page's identity key for a file (`readOne`): size, then CRC-32 of the first 64 KB and of the last 64 KB
    /// (none for a file of 128 KB or less), base 36. Nil for a file that can't be read.
    static func pageKey(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let size = try? h.seekToEnd() else { return nil }
        try? h.seek(toOffset: 0)
        guard let head = try? h.read(upToCount: 65536) ?? Data() else { return nil }
        var tail = Data()
        if size > 131072 { try? h.seek(toOffset: size - 65536); guard let t = try? h.read(upToCount: 65536) else { return nil }; tail = t }
        return String(size, radix: 36) + "-" + String(crc32(head), radix: 36) + "-" + String(crc32(tail), radix: 36)
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n); for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }; return c
    }

    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    /// A package (a Final Cut library, a Photos library; any folder the page sends as one thing) copied whole into
    /// `folder` under its own name: the same layout, every regular file through `copyVerified`, folders made, links
    /// kept as links (the same target text; a link holds no bytes of its own). Nothing is left out, dot-files
    /// included: a package is its maker's, not ours to thin. A different package already under that name is never
    /// mixed into: this one takes a numbered name ("Trip-2.fcpbundle").
    static func copyPackage(_ item: Item, folder: String, library: URL, lib: URL) -> Result {
        var r = Result(key: item.key, ok: false)
        let fm = FileManager.default
        let src = item.source.standardizedFileURL
        // Walked by name from the package's own path, so each entry's place inside it is exact (a listing by URL
        // spells a link that points nowhere differently from its neighbours). An entry that can't be read or told
        // apart stops the copy: nothing is skipped quietly.
        var unreadable = false
        var files: [(rel: String, url: URL, size: Int64)] = [], dirs: [String] = [], links: [(rel: String, to: String)] = []
        var todo = [""]
        while let dir = todo.popLast() {
            let at = dir.isEmpty ? item.source : item.source.appendingPathComponent(dir, isDirectory: true)
            guard let names = try? fm.contentsOfDirectory(atPath: at.path) else { unreadable = true; break }
            for name in names.sorted() {
                let rel = dir.isEmpty ? name : dir + "/" + name
                let u = item.source.appendingPathComponent(rel)
                guard name != "..", name != ".", let a = try? fm.attributesOfItem(atPath: u.path), let type = a[.type] as? FileAttributeType else { unreadable = true; continue }
                switch type {
                case .typeSymbolicLink:
                    guard let to = try? fm.destinationOfSymbolicLink(atPath: u.path) else { unreadable = true; continue }
                    links.append((rel, to))
                case .typeDirectory: dirs.append(rel); todo.append(rel)
                case .typeRegular: files.append((rel, u, (a[.size] as? NSNumber)?.int64Value ?? 0))
                default: unreadable = true
                }
            }
        }
        guard !unreadable else { r.why = "part of it can't be read"; return r }
        let parent = lib.appendingPathComponent(folder, isDirectory: true)
        let base = (src.lastPathComponent as NSString).deletingPathExtension, ext = src.pathExtension
        var dst = parent.appendingPathComponent(src.lastPathComponent, isDirectory: true), n = 2
        // Another package under that name: one whose file at the same place has other bytes, or whose link points elsewhere.
        func clashes(_ d: URL) -> Bool {
            guard fm.fileExists(atPath: d.path) else { return false }
            for f in files {
                let t = d.appendingPathComponent(f.rel)
                guard let a = try? fm.attributesOfItem(atPath: t.path) else { continue }
                if a[.type] as? FileAttributeType != .typeRegular || (a[.size] as? NSNumber)?.int64Value != f.size { return true }
                if (try? SetsFileOps.sha256(file: t)) != (try? SetsFileOps.sha256(file: f.url)) { return true }
            }
            for l in links { if let to = try? fm.destinationOfSymbolicLink(atPath: d.appendingPathComponent(l.rel).path), to != l.to { return true } }
            return false
        }
        while clashes(dst) { dst = parent.appendingPathComponent("\(base)-\(n)" + (ext.isEmpty ? "" : ".\(ext)"), isDirectory: true); n += 1 }
        do {
            var newBytes = !fm.fileExists(atPath: dst.path)
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            for d in dirs { try fm.createDirectory(at: dst.appendingPathComponent(d, isDirectory: true), withIntermediateDirectories: true) }
            for f in files {
                switch try SetsFileOps.copyVerified(f.url, to: dst.appendingPathComponent(f.rel)) {
                case .alreadyThere: break
                case .copied: newBytes = true
                case .renamed: throw SetsFileOps.Failure("\(f.rel) changed in the library while the package was copied")
                }
                r.files += 1; r.bytes += f.size
            }
            for l in links {
                let t = dst.appendingPathComponent(l.rel)
                if (try? fm.destinationOfSymbolicLink(atPath: t.path)) == l.to { continue }
                try fm.createDirectory(at: t.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.createSymbolicLink(atPath: t.path, withDestinationPath: l.to)
                newBytes = true
            }
            r.rel = String(dst.standardizedFileURL.path.dropFirst(lib.path.count + 1))
            r.sources = [src.path]
            r.ok = true
            r.already = !newBytes
        } catch where !fm.fileExists(atPath: library.path) {
            r.why = destinationGone
        } catch let e as SetsFileOps.Failure {
            r.why = e.description.contains("doesn't match") ? "copy doesn't match" : e.description.contains("changed while") ? "changed while copying" : e.description.contains("changed in the library") ? "library changed while copying" : "failed"
        } catch {
            r.why = SetsFileOps.reason(error)
        }
        return r
    }

    /// What the page skips as system files (`junk`): any part of the path a dot-name, `Thumbs.db`, `desktop.ini`.
    static func isSystemFile(_ rel: String) -> Bool {
        rel.split(separator: "/").contains { $0.hasPrefix(".") || $0 == "Thumbs.db" || $0 == "desktop.ini" }
    }

    /// "Safe to format" is said by the card, not by what was sent: every file under `root` (a card's root) that is
    /// not a system file must have a verified copy (`copied`: standardized source paths; a package copied whole is
    /// its folder's path and covers what is in it). Answers the files still
    /// only on the card, as paths under `root`, in order. Links and unreadable folders are listed too.
    static func unaccounted(under root: URL, copied: Set<String>) -> [String] {
        let base = root.standardizedFileURL.path
        var left: [String] = []
        var unreadable = false
        let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [],
                                                errorHandler: { u, _ in
            let rel = String(u.standardizedFileURL.path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !isSystemFile(rel) { unreadable = true }
            return true
        })
        while let u = en?.nextObject() as? URL {
            let p = u.standardizedFileURL.path
            let rel = String(p.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if isSystemFile(rel) { if u.hasDirectoryPath { en?.skipDescendants() }; continue }
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if v?.isDirectory == true, v?.isSymbolicLink != true {
                // a package copied whole (`copyPackage`): everything in it is accounted for
                if copied.contains(p) { en?.skipDescendants() }
                continue
            }
            if !copied.contains(p) { left.append(rel) }
        }
        if unreadable { left.append("(a folder that can't be read)") }
        return left.sorted()
    }
}
