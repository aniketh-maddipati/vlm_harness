import Foundation

/// Skim's pick in the app (LOCAL-CHANGES 280): the folders chosen in the panel, counted here before the page's file
/// input is answered. WebKit lists a picked folder in full before the page sees any of it, so a whole drive (the T7's
/// top level, a home folder) would hold the page for minutes with nothing on screen. Counting stops at `files`; past
/// `clips` clips, or when it stopped, the page shows its too-big card (`luminaSkimBig`) and the input is answered with
/// nothing until the user chooses: a smaller folder, or `first`, the first `clips` clips by path with their sidecars.
/// Read only: names, kinds and sizes. Foundation only.
nonisolated enum SkimPickScan {
    /// The page's own limits (`Component.BIG`).
    static let clips = 1500, files = 50_000

    struct Result: Equatable, Sendable {
        var name: String
        var clips: Int
        var bytes: Int64
        /// Files looked at; `cut` when the count stopped at the limit.
        var files: Int
        var cut: Bool
        var first: [URL]
        /// Each of `first`'s place as the page's folder input would give it (webkitRelativePath: the picked folder's name,
        /// then the path inside it), or its name for a file picked by itself.
        var rels: [String] = []
        /// What was picked in the panel (Add clips tells the page, for the Final Cut file's paths).
        var picked: [URL] = []
        var tooBig: Bool { cut || clips > SkimPickScan.clips }
        /// What the page's card says (`luminaSkimBig.show`).
        var json: [String: Any] { ["name": name, "n": clips, "bytes": bytes, "cut": cut ? files : 0] }
    }

    /// A clip by its name, as the page's `isClip` reads it (AppleDouble `._` files aside).
    static func isClip(_ name: String) -> Bool {
        guard !name.hasPrefix("._") else { return false }
        return ["mp4", "mov", "mxf", "m4v", "3gp"].contains((name as NSString).pathExtension.lowercased())
    }

    /// The clip a sidecar belongs to, as the page pairs them: C0001M01.XML → C0001.
    static func sidecarStem(_ name: String) -> String? {
        guard (name as NSString).pathExtension.lowercased() == "xml" else { return nil }
        let base = (name as NSString).deletingPathExtension
        if let r = base.range(of: #"M\d\d$"#, options: [.regularExpression, .caseInsensitive]) { return String(base[..<r.lowerBound]).uppercased() }
        return base.uppercased()
    }

    /// Counts what `urls` hold, folders all the way down, and stops at `maxFiles`. `progress` is called every
    /// 2,000 files with (files, clips); `stop` ends the count early (a newer pick).
    static func scan(_ urls: [URL], maxClips: Int = clips, maxFiles: Int = files,
                     progress: ((Int, Int) -> Void)? = nil, stop: () -> Bool = { false }) -> Result {
        var n = 0, nClips = 0, bytes: Int64 = 0, cut = false
        var found: [(String, URL)] = [], sidecars: [String: [URL]] = [:], rel: [URL: String] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        func take(_ u: URL, _ v: URLResourceValues?, under root: URL?) {
            n += 1
            let name = u.lastPathComponent
            if isClip(name) || sidecarStem(name) != nil { rel[u] = relPath(u, under: root) }
            if isClip(name) { nClips += 1; bytes += Int64(v?.fileSize ?? 0); found.append((u.path, u)) }
            else if let s = sidecarStem(name) { sidecars[s, default: []].append(u) }
            if n % 2000 == 0 { progress?(n, nClips) }
            if n >= maxFiles { cut = true }
        }
        outer: for url in urls {
            let v = try? url.resourceValues(forKeys: Set(keys + [.isDirectoryKey]))
            if v?.isDirectory != true { if v?.isRegularFile == true { take(url, v, under: nil) }; if cut { break }; continue }
            guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { continue }
            for case let u as URL in en {
                if stop() { cut = true; break outer }
                let rv = try? u.resourceValues(forKeys: Set(keys))
                guard rv?.isRegularFile == true else { continue }
                take(u, rv, under: url)
                if cut { break outer }
            }
        }
        found.sort { $0.0 < $1.0 }
        var first: [URL] = []
        for (_, u) in found.prefix(maxClips) {
            first.append(u)
            let stem = (u.lastPathComponent as NSString).deletingPathExtension.uppercased()
            first += (sidecars[stem] ?? []).filter { $0.deletingLastPathComponent() == u.deletingLastPathComponent() }
        }
        return Result(name: name(of: urls), clips: nClips, bytes: bytes, files: n, cut: cut, first: first, rels: first.map { rel[$0] ?? $0.lastPathComponent })
    }

    /// `u`'s place as webkitRelativePath gives it: "CARD/PRIVATE/M4ROOT/CLIP/C0001.MP4" for a file inside the picked folder
    /// CARD; the name alone for a file picked by itself.
    static func relPath(_ u: URL, under root: URL?) -> String {
        guard let root else { return u.lastPathComponent }
        let r = root.standardizedFileURL.path, p = u.standardizedFileURL.path
        let top = root.path == "/" ? ((try? root.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Disk") : root.lastPathComponent
        guard p.hasPrefix(r.hasSuffix("/") ? r : r + "/") else { return top + "/" + u.lastPathComponent }
        return top + "/" + String(p.dropFirst(r.hasSuffix("/") ? r.count : r.count + 1))
    }

    /// The card's name: the folder or drive picked; "These clips" for several things or loose clips.
    static func name(of urls: [URL]) -> String {
        guard urls.count == 1, let u = urls.first, (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return "These clips" }
        if u.path == "/" { return (try? u.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "This disk" }
        return u.lastPathComponent
    }
}

extension SkimPickScan {
    /// Set by a newer pick: the count it would replace stops.
    nonisolated final class Stop: @unchecked Sendable {
        private let lock = NSLock(); private var on = false
        func set() { lock.lock(); on = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return on }
    }
}
