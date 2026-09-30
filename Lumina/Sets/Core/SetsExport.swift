import Foundation

/// Executes the page's `writeInto(files, label)` natively. The page builds the file list (names,
/// XMP bytes, which RAWs, which JPEG looks); this only decides *how* bytes land: backup first,
/// atomic, verified, never onto the card, with a journal so a crash mid-export is visible later.
nonisolated struct SetsExportJob {
    enum Item {
        case bytes(name: String, data: Data)
        case copy(name: String, source: URL)
        /// v3's Edit look (a CSS filter string). Unused by v5.
        case jpeg(name: String, source: URL, css: String, px: String)
        /// The Edit step's look string rendered through LookPipeline (SetsLookExport). `px` nil =
        /// full size; the format follows the name's extension (jpg, tif, png).
        case look(name: String, source: URL, look: String, px: Int?)

        var name: String {
            switch self { case .bytes(let n, _), .copy(let n, _), .jpeg(let n, _, _, _), .look(let n, _, _, _): return n }
        }

        /// The original a copy or render is made from.
        var source: URL? {
            switch self { case .bytes: return nil; case .copy(_, let s), .jpeg(_, let s, _, _), .look(_, let s, _, _): return s }
        }
    }

    struct Result: Codable, Equatable {
        var n = 0
        var bak = 0
        var renamed = 0
        var folder = ""
        var failed: [String] = []
    }

    let label: String
    let destination: URL
    let items: [Item]

    /// Rough bytes needed: copies at source size, JPEGs at a generous 12 MB (a 16-bit TIFF at
    /// 160 MB), XMPs as-is.
    func bytesNeeded() -> Int64 {
        items.reduce(Int64(0)) { sum, item in
            switch item {
            case .bytes(_, let d): return sum + Int64(d.count)
            case .copy(_, let src): return sum + Int64((try? src.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            case .jpeg: return sum + 12 << 20
            case .look(let name, _, _, _): return sum + ((name as NSString).pathExtension.lowercased().hasPrefix("tif") ? 160 << 20 : 12 << 20)
            }
        }
    }

    /// An original that isn't there any more: its folder gone too means the card was pulled;
    /// the folder still there means the file itself was moved, renamed or deleted (Finder).
    static func missing(_ src: URL) -> String {
        let folder = src.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folder.path) else { return "the card was removed · re-insert it and export again" }
        return "\(src.lastPathComponent) is no longer in \(folder.lastPathComponent) · moved, renamed or deleted? Open the folder again and export"
    }

    /// Out of space, however Foundation phrases it (ENOSPC, or Cocoa's "not enough space").
    static func isDiskFull(_ error: Error) -> Bool {
        var e: NSError? = error as NSError
        while let n = e {
            if (n.domain == NSPOSIXErrorDomain && n.code == Int(ENOSPC)) || (n.domain == NSCocoaErrorDomain && n.code == NSFileWriteOutOfSpaceError) { return true }
            e = n.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// Where an item really lands, or why it may not: its name must stay inside the destination,
    /// and its folder — symlinks followed — must not be a source folder or on the card.
    static func landing(_ name: String, in destination: URL, sources: [URL]) -> Swift.Result<URL, SetsFileOps.Failure> {
        let base = destination.standardizedFileURL
        let dst = base.appendingPathComponent(name).standardizedFileURL
        guard dst.path.hasPrefix(base.path + "/") else { return .failure(.init("\(name): outside the export folder")) }
        var parent = dst.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: parent.path), parent.path != "/" { parent.deleteLastPathComponent() }
        if let why = SetsFileOps.refusal(destination: parent.resolvingSymlinksInPath(), sources: sources) { return .failure(.init(why)) }
        return .success(dst)
    }

    /// Runs the job. `progress` gets (done, total). A failure stops the job cleanly: files already
    /// written stay (each one verified), the journal says which ones. `sources`: the folders being
    /// culled (and the card), which no item may land in, even through a symlink.
    func run(journal: SetsExportJournal?, sources: [URL] = [], progress: (Int, Int) -> Void = { _, _ in }) -> Result {
        var r = Result(folder: destination.path)
        let needed = bytesNeeded(), margin = max(Int64(1 << 20), needed / 20)
        if let free = SetsFileOps.freeBytes(at: destination), free < needed + margin {
            r.failed.append("Not enough space in \(destination.lastPathComponent): needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)), \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free. Nothing was written.")
            return r
        }
        journal?.begin(label: label, destination: destination, names: items.map(\.name))
        for (i, item) in items.enumerated() {
            do {
                let dst = try Self.landing(item.name, in: destination, sources: sources).get()
                switch item {
                case .bytes(_, let data):
                    if try SetsFileOps.write(data, to: dst).backedUp { r.bak += 1 }
                case .copy(_, let src):
                    if case .renamed = try SetsFileOps.copyVerified(src, to: dst) { r.renamed += 1 }
                case .jpeg(_, let src, let css, let px):
                    let jpg = try SetsEditLook.renderJPEG(raw: src, css: css, px: px)
                    if try SetsFileOps.write(jpg, to: dst).backedUp { r.bak += 1 }
                case .look(let name, let src, let look, let px):
                    let data = try SetsLookExport.render(raw: src, look: look, px: px, format: (name as NSString).pathExtension)
                    if try SetsFileOps.write(data, to: dst).backedUp { r.bak += 1 }
                }
                r.n += 1
                journal?.done(item.name)
            } catch {
                if let src = item.source, !FileManager.default.fileExists(atPath: src.path) {
                    r.failed.append(Self.missing(src))
                } else if Self.isDiskFull(error) {
                    r.failed.append("\(destination.lastPathComponent) is full · every file written before this one is complete and checked")
                } else {
                    r.failed.append("\(item.name): \(error)")
                }
                journal?.finish(ok: false)
                return r
            }
            progress(i + 1, items.count)
        }
        journal?.finish(ok: true)
        return r
    }
}

/// One JSON file per export in Application Support. Written before the first file and after every
/// file, so after a crash the next launch can say what was done and what wasn't (checklist F10).
nonisolated final class SetsExportJournal {
    struct Entry: Codable {
        var id: String
        var label: String
        var destination: String
        var started: Date
        var finished: Date?
        var ok: Bool?
        var planned: [String]
        var done: [String]
        /// Set by `recover` on the launch after a crash: the leftovers were cleaned up.
        var recovered: Date?
        var tempsRemoved: Int?
    }

    let url: URL
    private var entry: Entry?

    init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("export-\(Int(Date().timeIntervalSince1970 * 1000)).json")
    }

    func begin(label: String, destination: URL, names: [String]) {
        entry = Entry(id: url.deletingPathExtension().lastPathComponent, label: label, destination: destination.path,
                      started: Date(), planned: names, done: [])
        save()
    }

    func done(_ name: String) { entry?.done.append(name); save() }

    func finish(ok: Bool) { entry?.finished = Date(); entry?.ok = ok; save() }

    private func save() {
        guard let entry else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = .prettyPrinted
        if let data = try? enc.encode(entry) { try? SetsFileOps.replaceOwn(data, at: url) }
    }

    /// On launch: every export a crash or kill cut short gets its half-written temp files removed
    /// from the destination (only Lumina's own `.<planned name>.lumina-tmp-*`, nothing else), and
    /// is marked recovered. Finished files stay: each was verified before it was renamed into place.
    /// The journal keeps saying what was done and what wasn't. Returns the recovered exports.
    @discardableResult
    static func recover(in directory: URL) -> [Entry] {
        let fm = FileManager.default
        // A journal write cut short leaves its own temp file.
        for f in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] where f.hasPrefix(".export-") && f.contains(".lumina-tmp-") {
            try? fm.removeItem(at: directory.appendingPathComponent(f))
        }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = .prettyPrinted
        var out: [Entry] = []
        for url in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("export-") {
            guard var e = try? dec.decode(Entry.self, from: Data(contentsOf: url)), e.ok != true, e.recovered == nil else { continue }
            let dest = URL(fileURLWithPath: e.destination)
            var removed = 0
            var dirs: Set<String> = []
            for name in e.planned { dirs.insert(dest.appendingPathComponent(name).deletingLastPathComponent().path) }
            let planned = Set(e.planned.map { dest.appendingPathComponent($0).lastPathComponent })
            for d in dirs {
                for f in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where f.hasPrefix(".") && f.contains(".lumina-tmp-") {
                    // ".<name>.lumina-tmp-XXXXXXXX", where <name> is a planned file or its .lumina-bak
                    let base = String(f.dropFirst()).components(separatedBy: ".lumina-tmp-")[0]
                    let owner = base.hasSuffix(SetsFileOps.backupSuffix) ? String(base.dropLast(SetsFileOps.backupSuffix.count)) : base
                    guard planned.contains(owner) || planned.contains(where: { isNumberedCopy(owner, of: $0) }) else { continue }
                    if (try? fm.removeItem(atPath: (d as NSString).appendingPathComponent(f))) != nil { removed += 1 }
                }
            }
            e.recovered = Date(); e.tempsRemoved = removed
            if let data = try? enc.encode(e) { try? SetsFileOps.replaceOwn(data, at: url) }
            out.append(e)
        }
        return out.sorted { $0.started > $1.started }
    }

    /// "DSC00001-2.ARW" is the numbered copy `copyVerified` makes of "DSC00001.ARW" on a name clash.
    private static func isNumberedCopy(_ name: String, of planned: String) -> Bool {
        let stem = (planned as NSString).deletingPathExtension, ext = (planned as NSString).pathExtension
        guard name.hasPrefix(stem + "-"), name.hasSuffix(ext.isEmpty ? "" : "." + ext) else { return false }
        let mid = name.dropFirst(stem.count + 1).dropLast(ext.isEmpty ? 0 : ext.count + 1)
        return !mid.isEmpty && mid.allSatisfy(\.isNumber)
    }

    /// Exports that never finished, newest first.
    static func unfinished(in directory: URL) -> [Entry] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("export-") }
            .compactMap { try? dec.decode(Entry.self, from: Data(contentsOf: $0)) }
            .filter { $0.ok != true }
            .sorted { $0.started > $1.started }
    }
}
