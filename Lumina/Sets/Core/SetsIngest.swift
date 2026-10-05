import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reading a folder or card natively (the page's `onDir`, done by the Mac). The page still parses
/// and measures with `lumina-core`; this only decides how bytes come off the disk:
/// - the directory listing comes first, so the page knows the total before any photo is read;
/// - each file gives a 256 KB head (EXIF + preview offsets) and nothing else up front;
/// - a preview that starts inside the head (a Sony ARW's does, at about 130 KB) is not read from the
///   card twice: the head is kept for a moment and the preview read starts where the head ended;
/// - the embedded preview is read by byte range when asked, turned upright natively, and never
///   held by the page: it reads it once to make and measure its grid thumbnail (its own
///   createImageBitmap resize, so `lumina-core`'s measure sees the prototype's exact pixels) and
///   keeps only a URL for the large view;
/// - the grid thumbnail is made here too (`thumb`: upright, covering 720 × 480, a 0.9 JPEG), off the
///   page's main thread; the page's 360 px measuring bitmap stays its own;
/// - previews around the cursor are prefetched into an NSCache;
/// - reads bypass the buffer cache (F_NOCACHE) and run `workers` at a time, tied to the cores;
/// - when a card goes away every read for it stops at once and reports `gone`.
///
/// Thread-safe: the scheme handler calls in from its own queue, the bridge from the main actor.
nonisolated final class SetsIngest: @unchecked Sendable {
    static let headBytes = 262_144

    struct Failure: Error, CustomStringConvertible {
        enum Kind { case notFound, gone, bad }
        let kind: Kind
        let description: String
        init(_ kind: Kind, _ d: String) { self.kind = kind; description = d }
    }

    /// A byte range of one file's embedded JPEG, and how to turn it upright.
    struct Preview: Hashable {
        let rel: String
        let offset: Int
        let length: Int
        let orientation: Int
    }

    struct Stats {
        var workers = 0
        var inFlight = 0
        var maxInFlight = 0
        var heads = 0
        var previews = 0
        var thumbs = 0
        var cacheHits = 0
        var prefetched = 0
        var bytesRead: Int64 = 0
        /// Preview bytes taken from a head already read, instead of the card.
        var bytesFromHead: Int64 = 0
        /// The longest single read. A head or a preview: never a whole RAW.
        var largestRead = 0
        /// Files opened on a root after it was marked gone: must stay 0.
        var opensAfterGone = 0
        var failures = 0
        var gone: [String] = []

        var dictionary: [String: Any] {
            ["workers": workers, "inFlight": inFlight, "maxInFlight": maxInFlight, "heads": heads, "previews": previews, "thumbs": thumbs, "cacheHits": cacheHits, "prefetched": prefetched, "bytesRead": bytesRead, "bytesFromHead": bytesFromHead, "largestRead": largestRead,
             "opensAfterGone": opensAfterGone, "failures": failures, "gone": gone]
        }
    }

    /// Reads at a time, tied to the cores: the card itself is serial, but turning previews upright
    /// and the page's own decodes overlap with it.
    let workers: Int
    private let lock = NSLock()
    private var roots: [String: URL] = [:]
    /// Each root's paths as `resolve` compares them and `read` opens below them, worked out at `register`.
    private var rootPaths: [String: RootPath] = [:]
    /// Roots that are not a whole folder but some files in one (photos dropped or picked one by
    /// one, AirDrop arrivals in Downloads): the file names that may be read, by root name. Nothing
    /// else in that folder is listed, read or named: the user granted those files, not the folder.
    private var only: [String: Set<String>] = [:]
    private var gone: Set<String> = []
    private var stats = Stats()
    private let previewCache: NSCache<NSString, NSData>
    /// Heads just read, by `rel`: the page asks for a file's preview right after its head.
    private let headCache: NSCache<NSString, NSData>
    private let readQueue = OperationQueue()
    private let prefetchQueue = OperationQueue()

    /// `previews`, `heads`: the two caches. The app never passes them. A test does: an NSCache
    /// may drop anything at any moment under memory pressure, so a test of "the second ask is not
    /// read from the card again" needs a cache that keeps what it was given, and a test of "a dropped
    /// entry is read again" one that keeps nothing.
    init(workers: Int? = nil, previews: NSCache<NSString, NSData> = .init(), heads: NSCache<NSString, NSData> = .init()) {
        previewCache = previews
        headCache = heads
        // A switch for the probe and Debug builds only (S4): the app's Release build has no such
        // read, so it always takes the default below.
        #if DEBUG || LUMINA_TOOLS
        let env = ProcessInfo.processInfo.environment["LUMINA_INGEST_WORKERS"].flatMap(Int.init)
        #else
        let env: Int? = nil
        #endif
        self.workers = max(1, workers ?? env ?? min(8, max(2, ProcessInfo.processInfo.activeProcessorCount / 2)))
        stats.workers = self.workers
        readQueue.name = "lumina.ingest.read"
        readQueue.maxConcurrentOperationCount = self.workers
        readQueue.qualityOfService = .userInitiated
        prefetchQueue.name = "lumina.ingest.prefetch"
        prefetchQueue.maxConcurrentOperationCount = 2
        prefetchQueue.qualityOfService = .utility
        previewCache.totalCostLimit = 96 << 20           // ~100 previews: the cursor window, and what was read before a pull
        headCache.totalCostLimit = 24 << 20              // ~90 heads: far more than are between head and preview at once
    }

    // MARK: Roots

    /// A folder the user opened, known to the page by its name ("<name>/<file>"). `name`: another
    /// name for it, when a shoot holds two folders called the same (its second "100MSDCF"). `files`:
    /// the root is only these files of the folder (plain names, no path), not the folder itself.
    func register(_ url: URL, as name: String? = nil, only files: Set<String>? = nil) {
        let paths = RootPath(url)                        // one realpath here, not one per read
        let name = name ?? url.lastPathComponent
        lock.withLock {
            roots[name] = url
            rootPaths[name] = paths
            only[name] = files.map { Set($0.filter(Self.isPlainName)) }
            gone.remove(name)
            headCache.removeAllObjects()                 // another card can hold the same names
            stats.gone = gone.sorted()
        }
    }

    /// One file's own name: no folder, no `..`, not hidden.
    static func isPlainName(_ n: String) -> Bool {
        !n.isEmpty && !n.contains("/") && !n.hasPrefix(".") && !n.utf8.contains(0)
    }

    /// The whole folders opened. A root that is only some files of a folder is not one of them.
    var rootURLs: [URL] { lock.withLock { roots.filter { only[$0.key] == nil }.map(\.value) } }

    /// The files of the roots that are only some files of a folder.
    var looseURLs: [URL] {
        lock.withLock { only.flatMap { name, files in roots[name].map { r in files.map { r.appendingPathComponent($0) } } ?? [] } }
    }

    /// The file names a root is limited to, or nil for a whole folder (and for an unknown name).
    func allowed(named name: String) -> Set<String>? { lock.withLock { only[name] } }

    func root(named name: String) -> URL? { lock.withLock { roots[name] } }

    /// `<root name>/<path inside it>` → file URL, refusing anything that climbs out of the root.
    /// The one gate for every native read of a photo (head, preview, thumbnail, the Edit render, the
    /// canvas, export): `../` out of the root is refused, and so is ANY symbolic link below the root,
    /// a linked folder on the way or the file itself, wherever it points, inside the shoot or out
    /// (a camera never writes one, and refusing them all needs no second look at where one leads).
    /// The root is the folder the user chose: it may itself be reached through a link.
    /// A file that is no longer there still resolves, so the caller can say "gone" or "missing".
    /// Hard links can't be told apart from the file itself: accepted.
    func resolve(_ rel: String) -> URL? { locate(rel)?.url }

    /// A root's two paths. `plain` is what `resolve` compares with; `real` has every link on the way
    /// to the root resolved, so `read` can open below it with no link allowed anywhere in the path.
    private struct RootPath {
        let plain: String
        var real: String?

        init(_ url: URL) { plain = SetsIngest.plainPath(url); real = Self.realPath(url) }

        /// nil while the folder isn't there (a card not in the reader yet): asked again when needed.
        static func realPath(_ url: URL) -> String? {
            guard let p = realpath(url.path, nil) else { return nil }
            defer { free(p) }
            return String(cString: p)
        }
    }

    /// `resolve`, plus the same file below the root's real path (what `read` opens).
    private func locate(_ rel: String) -> (url: URL, real: String)? {
        let parts = rel.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let (root, known) = lock.withLock({ () -> (URL, RootPath)? in
            guard let r = roots[parts[0]], let k = rootPaths[parts[0]] else { return nil }
            // A root of single files: one of them, by its own name, and nothing else in the folder.
            if let files = only[parts[0]], !files.contains(parts[1]) { return nil }
            return (r, k)
        }) else { return nil }
        let url = root.appendingPathComponent(parts[1]).standardizedFileURL
        // Compared as plain paths: a file that no longer exists keeps a /private prefix its folder loses.
        let plain = Self.plainPath(url)
        guard plain.hasPrefix(known.plain + "/") else { return nil }
        var real = known.real
        if real == nil, let now = RootPath.realPath(root) {     // the folder appeared since `register`
            real = now
            lock.withLock { if roots[parts[0]] == root { rootPaths[parts[0]]?.real = now } }
        }
        // One lstat per name below the root (two for a DCIM-style path), none for the root itself.
        // It stops at the first name that isn't there: nothing below that can be a link, and a pulled
        // card (the root itself missing) still gets its URL back, for `lost` to call it gone.
        var path = real ?? root.standardizedFileURL.path
        var checking = true
        for part in plain.dropFirst(known.plain.count + 1).split(separator: "/") {
            path += "/" + part
            guard checking else { continue }
            var st = stat()
            guard lstat(path, &st) == 0 else { checking = false; continue }
            if (st.st_mode & S_IFMT) == S_IFLNK { return nil }
        }
        return (url, path)
    }

    /// The volume went away (card pulled or ejected): every root on it stops reading now.
    /// Returns the names of the roots that were stopped.
    @discardableResult
    func markGone(volume: URL) -> [String] {
        let v = Self.plainPath(volume)
        let names: [String] = lock.withLock {
            let hit = roots.filter { Self.plainPath($0.value) == v || Self.plainPath($0.value).hasPrefix(v + "/") }.map(\.key)
            gone.formUnion(hit)
            stats.gone = gone.sorted()
            return hit
        }
        if !names.isEmpty { prefetchQueue.cancelAllOperations(); headCache.removeAllObjects() }
        return names
    }

    /// The volume came back (same mount point): its roots read again, so previews of photos
    /// already read show without reading the folder again.
    @discardableResult
    func revive(volume: URL) -> [String] {
        let v = Self.plainPath(volume)
        return lock.withLock {
            let hit = roots.filter { gone.contains($0.key) && Self.plainPath($0.value).hasPrefix(v + "/") && FileManager.default.fileExists(atPath: $0.value.path) }.map(\.key)
            gone.subtract(hit)
            stats.gone = gone.sorted()
            return hit
        }
    }

    /// A path to compare volumes by. `standardizedFileURL` drops a leading /private only while the
    /// path exists, so a pulled card and its folders would stop matching; always drop it.
    static func plainPath(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        return p.hasPrefix("/private/") ? String(p.dropFirst("/private".count)) : p
    }

    func isGone(_ rel: String) -> Bool {
        let name = String(rel.split(separator: "/", maxSplits: 1).first ?? "")
        return lock.withLock { gone.contains(name) }
    }

    var snapshot: Stats { lock.withLock { stats } }

    // MARK: Listing (first, before any read)

    struct Listing {
        var name: String
        var files: [(rel: String, size: Int)] = []
        var xmp: [(rel: String, text: String)] = []
        /// Every other file's path (JPEG, HEIF, other RAWs, videos…): names only, never read. The
        /// page's intake() counts them for its import notes and the no-ARW message.
        var others: [String] = []
        /// On a card or removable volume: the page keeps Save off (SAFETY.md 4).
        var onCard = false
        /// Sidecars left unread because they are over `Limits.sidecarBytes`: their paths. The page
        /// counts them with its unreadable files.
        var skippedXmp: [String] = []
        /// Sidecars that are there but are not UTF-8 text (Latin-1, UTF-16, binary): their paths.
        /// The page gets no text for them, so it has to be told they exist: Save leaves them alone
        /// (`SetsFileOps.sidecarUnreadable`) instead of writing a fresh sidecar over them.
        var unreadableXmp: [String] = []
        /// Set when the listing stopped before the end. A stopped listing carries no files, so part
        /// of a folder never reaches the page looking like all of it.
        var stopped: Stop?

        var dictionary: [String: Any] {
            ["name": name, "files": files.map { ["rel": $0.rel, "size": $0.size] }, "xmp": xmp.map { ["rel": $0.rel, "text": $0.text] },
             "others": others, "onCard": onCard, "skippedXmp": skippedXmp, "unreadableXmp": unreadableXmp]
        }
    }

    enum Stop: String, Equatable {
        /// More than `Limits.entries` files and folders.
        case tooManyFiles
        /// A folder more than `Limits.depth` levels below the opened one.
        case tooDeep
        /// Another folder was opened while this one was being listed.
        case cancelled
    }

    /// How much of a folder a listing walks and reads before it gives up (threat model T5).
    struct Limits {
        /// Files and folders seen, counted before any filter. A shoot is a RAW, often a JPEG and a
        /// sidecar per frame: a 512 GB card of 24 MP ARWs holds about 20,000 frames (60,000
        /// entries), so 100,000 is a card and a half in one folder. The walk runs at about 60,000
        /// entries a second on an M-series SSD (`SetsIngestBoundsTests` measures it), so `/`, a home
        /// folder or a whole disk is refused in under 2 s, and `others` stays at about 10 MB of paths.
        var entries = 100_000
        /// Folder levels below the opened one. A card is 2 deep (DCIM/100MSDCF); an archive opened
        /// at its year (2026/09 wedding/day 1/card A/DCIM/100MSDCF) is 6. 12 is twice that; deeper
        /// trees (system folders, source checkouts, app data) are not shoots, and are refused as
        /// soon as the walk reaches one instead of at the entry count.
        var depth = 12
        /// A sidecar is read whole and handed to the page as text. Lightroom's, with a full develop
        /// history, is tens of KB: 1 MB is far past any real one. Larger ones are not read at all.
        var sidecarBytes = SetsFileOps.sidecarMaxBytes
    }

    /// macOS refused to list the folder (Privacy & Security → Files and Folders, SAFETY.md 5).
    static func accessDenied(_ root: URL) -> Bool {
        // Probe only (`open-slow-disk.json`): stands in for a disk whose first directory read is slow
        // (just mounted, asleep), so the test can check the caller is not the main thread. Not in
        // the app's Release build (S4).
        #if DEBUG || LUMINA_TOOLS
        if let ms = ProcessInfo.processInfo.environment["LUMINA_SLOW_DIR_MS"].flatMap(Double.init), ms > 0 { Thread.sleep(forTimeInterval: ms / 1000) }
        #endif
        do { _ = try FileManager.default.contentsOfDirectory(atPath: root.path); return false } catch {
            let ns = error as NSError, under = ns.userInfo[NSUnderlyingErrorKey] as? NSError
            return ns.code == NSFileReadNoPermissionError || [Int(EPERM), Int(EACCES)].contains(under?.code ?? 0)
        }
    }

    /// Every ARW or DNG under `root` (and its .xmp sidecars, read now: they're small), the way WebKit's
    /// folder input lists it: recursive, hidden files and AppleDouble `._` stubs skipped. Other
    /// files are listed by name only. Lumina's own `.lumina-bak` files are left out.
    /// A sidecar that is not UTF-8 text is named in `unreadableXmp`, without its text.
    /// Bounded by `limits`: a sidecar over the size is not read and is named in `skippedXmp`; past
    /// the entry count or the depth the listing stops, empty, with `stopped` set. Cancellable:
    /// `isCancelled` (by default, the calling task's cancellation) is checked as it walks.
    ///
    /// `name`: the root's name in the page's paths when it is not the folder's own. `only`: the root
    /// is these files of the folder (see `register`): the folder is not walked at all, each name is
    /// looked at by itself, and a name that is not a regular file there (gone, a link, a folder) is
    /// left out. Sidecars are only read when they are among the names.
    static func list(_ root: URL, name: String? = nil, only: Set<String>? = nil, limits: Limits = Limits(), isCancelled: () -> Bool = { Task.isCancelled }) -> Listing {
        var out = Listing(name: name ?? root.lastPathComponent)
        out.onCard = SetsFileOps.isCard(root)
        if let only {
            for file in only.filter(isPlainName).sorted().prefix(limits.entries) {
                let url = root.appendingPathComponent(file)
                var st = stat()
                guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, !file.hasSuffix(SetsFileOps.backupSuffix) else { continue }
                let ext = url.pathExtension.lowercased(), rel = out.name + "/" + file, size = Int(st.st_size)
                if ext == "arw" || ext == "dng" { out.files.append((rel, size)) }
                else if ext != "xmp" { out.others.append(rel) }
                else if size > limits.sidecarBytes { out.skippedXmp.append(rel) }
                else {
                    switch readAtMost(url, limits.sidecarBytes) {
                    case .some(.some(let data)):
                        if let text = String(data: data, encoding: .utf8) { out.xmp.append((rel, text)) } else { out.unreadableXmp.append(rel) }
                    case .some(.none): out.skippedXmp.append(rel)
                    case .none: break
                    }
                }
            }
            return out
        }
        let base = root.standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : base + "/"          // "/" itself opened
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return out }
        let stop = { (why: Stop) -> Listing in
            var empty = Listing(name: out.name)
            empty.onCard = out.onCard
            empty.stopped = why
            return empty
        }
        var seen = 0
        for case let url as URL in e {
            seen += 1
            if seen > limits.entries { return stop(.tooManyFiles) }
            if seen & 127 == 0, isCancelled() { return stop(.cancelled) }
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isDirectory == true {
                if url.standardizedFileURL.path.dropFirst(prefix.count).split(separator: "/").count > limits.depth { return stop(.tooDeep) }
                continue
            }
            let name = url.lastPathComponent
            guard !name.hasPrefix("._") else { continue }
            let ext = url.pathExtension.lowercased()
            guard !name.hasSuffix(SetsFileOps.backupSuffix) else { continue }
            guard v.isRegularFile == true else { continue }
            let inside = String(url.standardizedFileURL.path.dropFirst(prefix.count))
            let rel = out.name + "/" + inside
            if ext != "arw" && ext != "dng" && ext != "xmp" {
                out.others.append(rel)
            } else if ext == "arw" || ext == "dng" {
                out.files.append((rel, v.fileSize ?? 0))
            } else if (v.fileSize ?? 0) > limits.sidecarBytes {
                out.skippedXmp.append(rel)                          // the size is enough: never read to find out
            } else {
                switch readAtMost(url, limits.sidecarBytes) {
                case .some(.some(let data)):
                    if let text = String(data: data, encoding: .utf8) { out.xmp.append((rel, text)) }
                    else { out.unreadableXmp.append(rel) }          // there, but not text: named, so Save won't replace it
                case .some(.none): out.skippedXmp.append(rel)       // grew past the limit after the listing saw it
                case .none: break                                   // unreadable: left out, as before
                }
            }
        }
        if isCancelled() { return stop(.cancelled) }
        return out
    }

    /// The whole file if it is at most `max` bytes (`.some(data)`), `.some(nil)` if it is longer, nil
    /// if it can't be read. Never holds more than `max + 1` bytes.
    private static func readAtMost(_ url: URL, _ max: Int) -> Data?? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: max + 1) else { return nil }
        return .some(data.count > max ? nil : data)
    }

    // MARK: Reads (called off the main thread)

    /// The first 256 KB of a file (less if the file is shorter).
    func head(_ rel: String) throws -> Data {
        let data = try read(rel, offset: 0, length: Self.headBytes, allowShort: true)
        lock.withLock { stats.heads += 1 }
        headCache.setObject(data as NSData, forKey: rel as NSString, cost: data.count)
        return data
    }

    /// The embedded preview, upright: as stored, or turned and saved again as a 0.92 JPEG when the
    /// camera was turned (what the page's own canvas step made). The page reads it once to make
    /// its grid thumbnail and measure it, then only ever holds its URL for the large view.
    func preview(_ p: Preview) throws -> Data {
        let key = Self.key(p, upright: true) as NSString
        if let hit = previewCache.object(forKey: key) { lock.withLock { stats.cacheHits += 1 }; return hit as Data }
        let jpeg = try previewBytes(p, cache: ![3, 6, 8].contains(p.orientation))
        var out = jpeg
        if [3, 6, 8].contains(p.orientation) {
            // As the page does it: turned on a canvas, saved again as a 0.92 JPEG.
            guard let upright = Self.upright(jpeg: jpeg, orientation: p.orientation, quality: 0.92) else { throw Failure(.bad, "preview doesn't decode") }
            out = upright
            previewCache.setObject(out as NSData, forKey: key, cost: out.count)
        }
        lock.withLock { stats.previews += 1 }
        return out
    }

    /// The grid thumbnail: the embedded preview upright, resized once by ImageIO to cover the largest
    /// tile on a Retina screen (see `thumbnail`), saved as a 0.9 JPEG. The page reads the preview
    /// (as stored) just before, so the bytes usually come from the cache, not the card.
    func thumb(_ p: Preview) throws -> Data {
        let jpeg = try previewBytes(p, cache: true)
        guard let out = Self.thumbnail(jpeg: jpeg, orientation: p.orientation) else { throw Failure(.bad, "preview doesn't decode") }
        lock.withLock { stats.thumbs += 1 }
        return out
    }

    /// Warms the cache with the previews around the cursor. A new call replaces the last one.
    func prefetch(_ list: [Preview]) {
        prefetchQueue.cancelAllOperations()
        for p in list where !isGone(p.rel) {
            if previewCache.object(forKey: Self.key(p, upright: true) as NSString) != nil { continue }
            prefetchQueue.addOperation { [weak self] in
                guard let self, !self.isGone(p.rel) else { return }
                if (try? self.preview(p)) != nil { self.lock.withLock { self.stats.prefetched += 1 } }
            }
        }
    }

    /// Runs `work` on the bounded read queue; `done` gets the result on the main thread.
    func enqueue(_ work: @escaping () throws -> Data, done: @escaping (Result<Data, Error>) -> Void) {
        readQueue.addOperation {
            let r = Result { try work() }
            DispatchQueue.main.async { done(r) }
        }
    }

    private func previewBytes(_ p: Preview, cache: Bool) throws -> Data {
        let key = Self.key(p, upright: false) as NSString
        if let hit = previewCache.object(forKey: key) { lock.withLock { stats.cacheHits += 1 }; return hit as Data }
        guard p.offset > 0, p.length > 0, p.length <= 64 << 20 else { throw Failure(.bad, "no preview range") }
        // The start of the preview usually came with the head: only the rest is read from the card.
        var data = Data()
        if p.offset < Self.headBytes, let head = headCache.object(forKey: p.rel as NSString) as Data?, head.count > p.offset {
            data = head.subdata(in: p.offset ..< min(head.count, p.offset + p.length))
            lock.withLock { stats.bytesFromHead += Int64(data.count) }
        }
        if data.count < p.length {
            data.append(try read(p.rel, offset: p.offset + data.count, length: p.length - data.count, allowShort: false))
        } else if isGone(p.rel) {
            throw Failure(.gone, "card removed")         // all of it was in the head: no read to notice the card went
        }
        if cache { previewCache.setObject(data as NSData, forKey: key, cost: data.count) }
        return data
    }

    private static func key(_ p: Preview, upright: Bool) -> String {
        "\(p.rel)|\(p.offset)|\(p.length)|\(upright ? p.orientation : 1)"
    }

    /// One positioned read, uncached by the OS. A missing root means the card went away.
    private func read(_ rel: String, offset: Int, length: Int, allowShort: Bool) throws -> Data {
        if isGone(rel) { throw Failure(.gone, "card removed") }
        guard let (url, real) = locate(rel) else { throw Failure(.notFound, "not in an opened folder: \(rel)") }
        lock.withLock {
            stats.inFlight += 1
            stats.maxInFlight = max(stats.maxInFlight, stats.inFlight)
            if gone.contains(String(rel.split(separator: "/").first ?? "")) { stats.opensAfterGone += 1 }
        }
        defer { lock.withLock { stats.inFlight -= 1 } }
        // Read-only, and no link is followed: `locate` has just checked, and the kernel checks again
        // at the open, so a folder swapped for a link in between is refused too. Darwin refuses a
        // link anywhere in the path (hence the root's real path); elsewhere only as the last name.
        #if canImport(Darwin)
        let fd = open(real, O_RDONLY | O_NOFOLLOW_ANY)
        #else
        let fd = open(real, O_RDONLY | O_NOFOLLOW)
        #endif
        guard fd >= 0 else { throw lost(rel, url, errno) }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        var buf = Data(count: length)
        var got = 0
        while got < length {
            let n = buf.withUnsafeMutableBytes { pread(fd, $0.baseAddress! + got, length - got, off_t(offset + got)) }
            if n < 0 { if errno == EINTR { continue }; throw lost(rel, url, errno) }
            if n == 0 { break }
            got += n
        }
        if got < length {
            guard allowShort else { lock.withLock { stats.failures += 1 }; throw Failure(.bad, "file ends inside the preview") }
            buf.count = got
        }
        lock.withLock { stats.bytesRead += Int64(got); stats.largestRead = max(stats.largestRead, got) }
        return buf
    }

    /// A read failed: if the root folder itself is gone, the card was pulled — say so, and stop
    /// every other read for that root.
    private func lost(_ rel: String, _ url: URL, _ code: Int32) -> Failure {
        let name = String(rel.split(separator: "/").first ?? "")
        if let root = root(named: name), !FileManager.default.fileExists(atPath: root.path) {
            lock.withLock { gone.insert(name); stats.gone = gone.sorted(); stats.failures += 1 }
            prefetchQueue.cancelAllOperations()
            return Failure(.gone, "card removed")
        }
        lock.withLock { stats.failures += 1 }
        return Failure(code == ENOENT ? .notFound : .bad, "\(url.lastPathComponent): \(String(cString: strerror(code)))")
    }

    // MARK: Decode

    private static func decode(_ jpeg: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }

    private static func encode(_ image: CGImage, _ type: UTType, quality: Double?) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary })
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// The largest tile is 216 × 1.5 = 324 × 216 CSS px (ADDENDUM-1 §4), 648 × 432 on a Retina screen.
    static let thumbBox = (w: 720, h: 480)

    /// A JPEG resized to cover `thumbBox` once upright (landscape tiles crop to fill, portrait ones fit
    /// the height), never upscaled, turned for EXIF orientation 3 / 6 / 8, saved at `quality`.
    static func thumbnail(jpeg: Data, orientation: Int, quality: Double = 0.9) -> Data? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
              let w = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue, w > 0, h > 0 else { return nil }
        let swap = orientation == 6 || orientation == 8
        let (uw, uh) = swap ? (Double(h), Double(w)) : (Double(w), Double(h))
        let s = min(1, uh > uw ? Double(thumbBox.h) / uh : max(Double(thumbBox.w) / uw, Double(thumbBox.h) / uh))
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: false,
                                     kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: Int((Double(max(w, h)) * s).rounded())]
        guard let small = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let image = [3, 6, 8].contains(orientation) ? turn(small, orientation) : small
        return image.flatMap { encode($0, .jpeg, quality: quality) }
    }

    /// Turns a JPEG upright for EXIF orientation 3 / 6 / 8 (exact quarter turns) and saves it again.
    static func upright(jpeg: Data, orientation: Int, quality: Double) -> Data? {
        decode(jpeg).flatMap { turn($0, orientation) }.flatMap { encode($0, .jpeg, quality: quality) }
    }

    private static func turn(_ image: CGImage, _ orientation: Int) -> CGImage? {
        let swap = orientation == 6 || orientation == 8
        let (w, h) = swap ? (image.height, image.width) : (image.width, image.height)
        guard let ctx = context(w, h) else { return nil }
        // Core Graphics is y-up: a clockwise turn on screen is a negative angle here.
        let angle: CGFloat = orientation == 6 ? -.pi / 2 : orientation == 8 ? .pi / 2 : orientation == 3 ? .pi : 0
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.rotate(by: angle)
        ctx.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        return ctx.makeImage()
    }
}
