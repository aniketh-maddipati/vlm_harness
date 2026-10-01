import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reading a folder or card natively (the page's `onDir`, done by the Mac). The page still parses
/// and measures with `lumina-core`; this only decides how bytes come off the disk:
/// - the directory listing comes first, so the page knows the total before any photo is read;
/// - each file gives a 256 KB head (EXIF + preview offsets) and nothing else up front;
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
        /// The longest single read. A head or a preview: never a whole RAW.
        var largestRead = 0
        /// Files opened on a root after it was marked gone: must stay 0.
        var opensAfterGone = 0
        var failures = 0
        var gone: [String] = []

        var dictionary: [String: Any] {
            ["workers": workers, "inFlight": inFlight, "maxInFlight": maxInFlight, "heads": heads, "previews": previews, "thumbs": thumbs, "cacheHits": cacheHits, "prefetched": prefetched, "bytesRead": bytesRead, "largestRead": largestRead,
             "opensAfterGone": opensAfterGone, "failures": failures, "gone": gone]
        }
    }

    /// Reads at a time, tied to the cores: the card itself is serial, but turning previews upright
    /// and the page's own decodes overlap with it.
    let workers: Int
    private let lock = NSLock()
    private var roots: [String: URL] = [:]
    private var gone: Set<String> = []
    private var stats = Stats()
    private let previewCache = NSCache<NSString, NSData>()
    private let readQueue = OperationQueue()
    private let prefetchQueue = OperationQueue()

    init(workers: Int? = nil) {
        let env = ProcessInfo.processInfo.environment["LUMINA_INGEST_WORKERS"].flatMap(Int.init)
        self.workers = max(1, workers ?? env ?? min(8, max(2, ProcessInfo.processInfo.activeProcessorCount / 2)))
        stats.workers = self.workers
        readQueue.name = "lumina.ingest.read"
        readQueue.maxConcurrentOperationCount = self.workers
        readQueue.qualityOfService = .userInitiated
        prefetchQueue.name = "lumina.ingest.prefetch"
        prefetchQueue.maxConcurrentOperationCount = 2
        prefetchQueue.qualityOfService = .utility
        previewCache.totalCostLimit = 96 << 20           // ~100 previews: the cursor window, and what was read before a pull
    }

    // MARK: Roots

    /// A folder the user opened, known to the page by its name ("<name>/<file>").
    func register(_ url: URL) {
        lock.withLock {
            roots[url.lastPathComponent] = url
            gone.remove(url.lastPathComponent)
            stats.gone = gone.sorted()
        }
    }

    var rootURLs: [URL] { lock.withLock { Array(roots.values) } }

    func root(named name: String) -> URL? { lock.withLock { roots[name] } }

    /// `<root name>/<path inside it>` → file URL, refusing anything that climbs out of the root.
    func resolve(_ rel: String) -> URL? {
        let parts = rel.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let root = root(named: parts[0]) else { return nil }
        let url = root.appendingPathComponent(parts[1]).standardizedFileURL
        // Compared as plain paths: a file that no longer exists keeps a /private prefix its folder loses.
        guard Self.plainPath(url).hasPrefix(Self.plainPath(root) + "/") else { return nil }
        return url
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
        if !names.isEmpty { prefetchQueue.cancelAllOperations() }
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

        var dictionary: [String: Any] {
            ["name": name, "files": files.map { ["rel": $0.rel, "size": $0.size] }, "xmp": xmp.map { ["rel": $0.rel, "text": $0.text] },
             "others": others, "onCard": onCard]
        }
    }

    /// macOS refused to list the folder (Privacy & Security → Files and Folders, SAFETY.md 5).
    static func accessDenied(_ root: URL) -> Bool {
        // Probe only (`open-slow-disk.json`): stands in for a disk whose first directory read is slow
        // (just mounted, asleep), so the test can check the caller is not the main thread.
        if let ms = ProcessInfo.processInfo.environment["LUMINA_SLOW_DIR_MS"].flatMap(Double.init), ms > 0 { Thread.sleep(forTimeInterval: ms / 1000) }
        do { _ = try FileManager.default.contentsOfDirectory(atPath: root.path); return false } catch {
            let ns = error as NSError, under = ns.userInfo[NSUnderlyingErrorKey] as? NSError
            return ns.code == NSFileReadNoPermissionError || [Int(EPERM), Int(EACCES)].contains(under?.code ?? 0)
        }
    }

    /// Every ARW under `root` (and its .xmp sidecars, read now: they're small), the way WebKit's
    /// folder input lists it: recursive, hidden files and AppleDouble `._` stubs skipped. Other
    /// files are listed by name only. Lumina's own `.lumina-bak` files are left out.
    static func list(_ root: URL) -> Listing {
        var out = Listing(name: root.lastPathComponent)
        out.onCard = SetsFileOps.isCard(root)
        let base = root.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return out }
        for case let url as URL in e {
            let name = url.lastPathComponent
            guard !name.hasPrefix("._") else { continue }
            let ext = url.pathExtension.lowercased()
            guard !name.hasSuffix(SetsFileOps.backupSuffix) else { continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let inside = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            let rel = out.name + "/" + inside
            if ext != "arw" && ext != "xmp" {
                out.others.append(rel)
            } else if ext == "arw" {
                out.files.append((rel, v.fileSize ?? 0))
            } else if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                out.xmp.append((rel, text))
            }
        }
        return out
    }

    // MARK: Reads (called off the main thread)

    /// The first 256 KB of a file (less if the file is shorter).
    func head(_ rel: String) throws -> Data {
        let data = try read(rel, offset: 0, length: Self.headBytes, allowShort: true)
        lock.withLock { stats.heads += 1 }
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
        let data = try read(p.rel, offset: p.offset, length: p.length, allowShort: false)
        if cache { previewCache.setObject(data as NSData, forKey: key, cost: data.count) }
        return data
    }

    private static func key(_ p: Preview, upright: Bool) -> String {
        "\(p.rel)|\(p.offset)|\(p.length)|\(upright ? p.orientation : 1)"
    }

    /// One positioned read, uncached by the OS. A missing root means the card went away.
    private func read(_ rel: String, offset: Int, length: Int, allowShort: Bool) throws -> Data {
        if isGone(rel) { throw Failure(.gone, "card removed") }
        guard let url = resolve(rel) else { throw Failure(.notFound, "not in an opened folder: \(rel)") }
        lock.withLock {
            stats.inFlight += 1
            stats.maxInFlight = max(stats.maxInFlight, stats.inFlight)
            if gone.contains(String(rel.split(separator: "/").first ?? "")) { stats.opensAfterGone += 1 }
        }
        defer { lock.withLock { stats.inFlight -= 1 } }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)            // read-only; a symlink is never followed out
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
