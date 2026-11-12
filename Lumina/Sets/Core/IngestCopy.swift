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
    }

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
        if let no = SetsFileOps.refusal(destination: library, sources: [item.root]) { r.why = no.hasPrefix("Pick a folder that isn't on the card") ? "library on the card" : "library inside the source"; return r }
        guard let folder = safeFolder(item.folder) else { r.why = "refused"; return r }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: item.source.path, isDirectory: &isDir), !isDir.boolValue else { r.why = "missing"; return r }
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
            switch out {
            case .alreadyThere(let u): target = u
            case .copied(let u), .renamed(let u): target = u; newBytes = true
            }
            r.files = 1
            r.bytes = Int64((try? item.source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            r.rel = String(target.standardizedFileURL.path.dropFirst(lib.path.count + 1))
            // Companions follow the main file's name in the library (a numbered main file numbers them too).
            let srcStem = (item.source.lastPathComponent as NSString).deletingPathExtension
            let dstStem = (target.lastPathComponent as NSString).deletingPathExtension
            for c in companions(of: item.source) {
                let rest = String(c.lastPathComponent.dropFirst(srcStem.count))
                let cd = target.deletingLastPathComponent().appendingPathComponent(dstStem + rest)
                switch try SetsFileOps.copyVerified(c, to: cd) {
                case .alreadyThere: break
                case .copied, .renamed: newBytes = true
                }
                r.files += 1
                r.bytes += Int64((try? c.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            if !item.key.isEmpty, let rel = r.rel { store.record(item.key, IngestLibrary.Entry(rel: rel, sha: sha, size: r.bytes)) }
            r.ok = true
            r.already = !newBytes
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
    private struct File: Codable { var path: String?; var bookmark: Data?; var keys: [String: Entry] = [:] }

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

    /// Forgets the identities (the page's Forget); the library's files are not touched.
    func forget() { lock.withLock { file.keys = [:] } }

    func save() throws {
        let data = try lock.withLock { try JSONEncoder().encode(file) }
        try SetsFileOps.replaceOwn(data, at: url)
    }
}

extension IngestCopy {
    /// Where the page's file is on disk. The page knows a file as its `webkitRelativePath` ("SONY/DCIM/100MSDCF/
    /// DSC01234.ARW": the chosen folder's name first) or, for files chosen on their own, its name. Only inside a
    /// folder or file the owner chose in Ingest's open panel (`roots`); no `..`, no leading `/`.
    static func resolve(_ path: String, roots: [URL]) -> (file: URL, root: URL)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.hasPrefix("/"), !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { return nil }
        let fm = FileManager.default
        for root in roots.reversed() {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard parts.count > 1, parts[0] == root.lastPathComponent else { continue }
                let f = root.appendingPathComponent(parts.dropFirst().joined(separator: "/"))
                let rp = root.standardizedFileURL.resolvingSymlinksInPath().path, fp = f.standardizedFileURL.resolvingSymlinksInPath().path
                guard fp.hasPrefix(rp + "/"), fm.fileExists(atPath: f.path) else { continue }
                return (f, root)
            } else if parts.count == 1, root.lastPathComponent == parts[0] {
                return (root, root.deletingLastPathComponent())
            }
        }
        return nil
    }
}
