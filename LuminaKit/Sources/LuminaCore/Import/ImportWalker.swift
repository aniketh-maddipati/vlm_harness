import Foundation

// WP-2. The part of an import that runs off the main thread (R-10…R-16, R-85): walk the folders,
// sort files by name and size, decode what might be a photo, drop what the shoot already has, and
// group the result. Nothing here touches the model; `AppModel.importURLs` applies the outcome.

/// A folder or loose file the user picked, kept so the shoot can be reopened after a relaunch (R-19).
public struct FolderRoot: Codable, Equatable, Sendable {
    public var path: String
    public var name: String
    public var isFolder: Bool
    /// Security-scoped where the system gives one, a plain bookmark otherwise.
    public var bookmark: Data?
    public init(path: String, name: String, isFolder: Bool, bookmark: Data? = nil) {
        self.path = path; self.name = name; self.isFolder = isFolder; self.bookmark = bookmark
    }
}

struct ImportRequest: Sendable {
    var urls: [URL]
    /// What the local shoot already holds: new photos are grouped together with these.
    var existing: [ImportItem]
    /// The local shoot's name so far; nil for a first import (the batch names it).
    var shootName: String?
}

struct ImportOutcome: Sendable {
    var accepted: [ImportItem] = []
    var skipped: [SkipReason: Int] = [:]
    /// The folder's name, or "Dropped photos" for loose files.
    var name = ImportWalker.looseName
    /// Nothing to look at: an empty folder, or only hidden files.
    var noFiles = false
    /// A folder or file could not be read at all.
    var unreadable = false
    var roots: [FolderRoot] = []
    /// Existing + accepted, grouped. Nil when nothing was accepted.
    var shoot: Shoot?
}

enum ImportWalker {
    static let looseName = "Dropped photos"

    struct File: Sendable { var url: URL; var rel: String; var size: Int64; var modified: Date? }

    /// Every regular file under `urls`, folders walked all the way down (R-15). Hidden files and
    /// the insides of packages are not listed: they are never photos to the person importing.
    static func files(_ urls: [URL]) -> (files: [File], name: String, roots: [FolderRoot], unreadable: Bool) {
        let fm = FileManager.default, keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        var out: [File] = [], roots: [FolderRoot] = [], folders: [String] = [], unreadable = false
        func add(_ u: URL, rel: String, _ v: URLResourceValues) {
            out.append(File(url: u, rel: rel, size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate))
        }
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { unreadable = true; continue }
            if v.isDirectory == true {
                let name = folderName(url)
                roots.append(FolderRoot(path: url.path, name: name, isFolder: true)); folders.append(name)
                guard let walk = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true })
                else { unreadable = true; continue }
                // The walk may spell the folder differently from how it was given (/var is /private/var).
                let bases = spellings(of: url)
                for case let f as URL in walk {
                    guard let fv = try? f.resourceValues(forKeys: Set(keys)), fv.isRegularFile == true else { continue }
                    let path = f.path
                    let inside = bases.first { path.hasPrefix($0) }.map { String(path.dropFirst($0.count)) } ?? f.lastPathComponent
                    add(f, rel: name + "/" + inside, fv)
                }
            } else if v.isRegularFile == true {
                roots.append(FolderRoot(path: url.path, name: url.lastPathComponent, isFolder: false))
                add(url, rel: url.lastPathComponent, v)
            }
        }
        // One folder names the import; otherwise the first file's folder; loose files have no name.
        let name = folders.count == 1 ? folders[0] : out.first.flatMap { $0.rel.contains("/") ? $0.rel.split(separator: "/").first.map(String.init) : nil } ?? looseName
        return (out, name, roots, unreadable)
    }

    /// The ways a folder's path can be written, each ending in "/", longest first.
    static func spellings(of url: URL) -> [String] {
        var paths = [url.path, url.resolvingSymlinksInPath().path, url.standardizedFileURL.path, "/private" + url.path]
        if let real = url.withUnsafeFileSystemRepresentation({ $0.flatMap { realpath($0, nil) } }) { paths.append(String(cString: real)); free(real) }
        return Array(Set(paths.map { $0.hasSuffix("/") ? $0 : $0 + "/" })).sorted { $0.count > $1.count }
    }

    static func folderName(_ url: URL) -> String {
        let n = url.lastPathComponent
        return n.isEmpty || n == "/" ? "Folder" : n
    }

    /// The whole check for one batch. `progress(checked, toCheck)` is called from worker threads,
    /// every few files.
    static func run(_ req: ImportRequest, progress: @escaping @Sendable (Int, Int) -> Void) async -> ImportOutcome {
        var o = ImportOutcome()
        let listed = files(req.urls)
        o.name = listed.name; o.unreadable = listed.unreadable
        var seen = Set(req.existing.map(\.dedupeKey))
        var candidates: [(file: File, item: ImportItem)] = []
        for f in listed.files {
            let name = f.url.lastPathComponent
            switch ImportClassifier.classify(name: name, size: f.size) {
            case .system, .sidecar: continue                                     // R-11: silent
            case .video: o.skipped[.video, default: 0] += 1
            case .archive: o.skipped[.archive, default: 0] += 1
            case .empty: o.skipped[.empty, default: 0] += 1
            case .other: o.skipped[.other, default: 0] += 1
            case .photo, .raw:
                let item = ImportItem(rel: f.rel, url: f.url, size: f.size, modified: f.modified)
                if seen.insert(item.dedupeKey).inserted { candidates.append((f, item)) } else { o.skipped[.duplicate, default: 0] += 1 }
            }
        }
        o.noFiles = listed.files.isEmpty
        guard !candidates.isEmpty else { return o }

        progress(0, candidates.count)
        let total = candidates.count, cursor = Cursor(), work = candidates
        // Leave a core for the window: keys stay quick while a big folder is checked (R-85).
        let workers = max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 1, total))
        let probed: [(Int, ImageProbe.Result?)] = await withTaskGroup(of: [(Int, ImageProbe.Result?)].self) { group in
            for _ in 0..<workers {
                group.addTask(priority: .utility) {
                    var mine: [(Int, ImageProbe.Result?)] = []
                    while let i = cursor.next(total) {
                        mine.append((i, autoreleasepool { ImageProbe.probe(work[i].file.url) }))
                        let done = cursor.finished()
                        if done % 8 == 0 || done == total { progress(done, total) }
                    }
                    return mine
                }
            }
            var all: [(Int, ImageProbe.Result?)] = []
            for await part in group { all += part }
            return all
        }
        for (i, r) in probed.sorted(by: { $0.0 < $1.0 }) {
            var item = candidates[i].item
            guard let r else {
                let heic = ["heic", "heif"].contains(candidates[i].file.url.pathExtension.lowercased())
                o.skipped[heic ? .heic : .damaged, default: 0] += 1
                continue
            }
            item.aspect = Double(r.info.pixelSize.width / r.info.pixelSize.height)
            item.exif = r.exif; item.shot = r.exif?.shot
            o.accepted.append(item)
        }
        guard !o.accepted.isEmpty else { return o }
        // Bookmarks are made here, off the main thread; a pile of loose files keeps paths only.
        o.roots = listed.roots.enumerated().map { i, root in
            var r = root; if r.isFolder || i < 200 { r.bookmark = FolderMemory.bookmark(URL(fileURLWithPath: r.path)) }; return r
        }
        o.shoot = SceneGrouper.group(req.existing + o.accepted, name: req.shootName ?? o.name)
        return o
    }

    private final class Cursor: @unchecked Sendable {
        private let lock = NSLock(); private var at = 0, done = 0
        func next(_ total: Int) -> Int? { lock.withLock { guard at < total else { return nil }; at += 1; return at - 1 } }
        func finished() -> Int { lock.withLock { done += 1; return done } }
    }
}
