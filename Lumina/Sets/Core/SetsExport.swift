import Foundation

/// Executes the page's `writeInto(files, label)` natively. The page builds the file list (names,
/// XMP bytes, which RAWs, which JPEG looks); this only decides *how* bytes land: backup first,
/// atomic, verified, never onto the card, with a journal so a crash mid-export is visible later.
nonisolated struct SetsExportJob {
    enum Item {
        case bytes(name: String, data: Data)
        case copy(name: String, source: URL)
        case jpeg(name: String, source: URL, css: String, px: String)

        var name: String {
            switch self { case .bytes(let n, _), .copy(let n, _), .jpeg(let n, _, _, _): return n }
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

    /// Rough bytes needed: copies at source size, JPEGs at a generous 12 MB, XMPs as-is.
    func bytesNeeded() -> Int64 {
        items.reduce(Int64(0)) { sum, item in
            switch item {
            case .bytes(_, let d): return sum + Int64(d.count)
            case .copy(_, let src): return sum + Int64((try? src.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            case .jpeg: return sum + 12 << 20
            }
        }
    }

    /// Runs the job. `progress` gets (done, total). A failure stops the job cleanly: files already
    /// written stay (each one verified), the journal says which ones.
    func run(journal: SetsExportJournal?, progress: (Int, Int) -> Void = { _, _ in }) -> Result {
        var r = Result(folder: destination.path)
        let needed = bytesNeeded(), margin = max(Int64(1 << 20), needed / 20)
        if let free = SetsFileOps.freeBytes(at: destination), free < needed + margin {
            r.failed.append("Not enough space in \(destination.lastPathComponent): needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)), \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free. Nothing was written.")
            return r
        }
        journal?.begin(label: label, destination: destination, names: items.map(\.name))
        for (i, item) in items.enumerated() {
            let dst = destination.appendingPathComponent(item.name)
            do {
                switch item {
                case .bytes(_, let data):
                    if try SetsFileOps.write(data, to: dst).backedUp { r.bak += 1 }
                case .copy(_, let src):
                    if case .renamed = try SetsFileOps.copyVerified(src, to: dst) { r.renamed += 1 }
                case .jpeg(_, let src, let css, let px):
                    let jpg = try SetsEditLook.renderJPEG(raw: src, css: css, px: px)
                    if try SetsFileOps.write(jpg, to: dst).backedUp { r.bak += 1 }
                }
                r.n += 1
                journal?.done(item.name)
            } catch {
                if case .copy(_, let src) = item, !FileManager.default.fileExists(atPath: src.path) {
                    r.failed.append("the card was removed · re-insert it and export again")
                } else if case .jpeg(_, let src, _, _) = item, !FileManager.default.fileExists(atPath: src.path) {
                    r.failed.append("the card was removed · re-insert it and export again")
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
