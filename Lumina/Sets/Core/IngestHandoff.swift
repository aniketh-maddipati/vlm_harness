import Foundation

/// The ingest prototype's Open in Pick (Debug builds, `LUMINA_PAGE=ingest`): which folder Pick opens for what the
/// ingest page shows, and which of its files. Foundation only.
///
/// The page knows files as "<what was dropped or picked>/<path inside it>" ("burst-10fps/DSC0001.ARW"), or a loose
/// file's name; the window knows the URLs it handed over (`roots`: the open panel's picks and the drops). Pick opens
/// one folder: the deepest one holding every file, and only when that is one of the roots or inside one (the app can
/// read nothing above what the user handed over).
enum IngestHandoff {
    struct Plan: Equatable {
        /// The folder Pick opens, as if the user had picked it.
        var folder: URL
        /// The files in it to read ("sub/DSC0001.ARW"), or nil for all of it.
        var only: Set<String>?
    }

    /// `whole`: the page shows everything it read (no find).
    static func plan(paths: [String], whole: Bool, roots: [URL]) -> Result<Plan, Refusal> {
        let roots = roots.map(\.standardizedFileURL)
        var files: [URL] = [], used: [URL] = []
        for p in paths {
            let parts = p.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let first = parts.first, !parts.contains(".."), !parts.contains("."),
                  let root = roots.last(where: { $0.lastPathComponent == first }) else { return .failure(.unknown) }
            files.append(parts.dropFirst().reduce(root) { $0.appendingPathComponent($1) })
            if !used.contains(root) { used.append(root) }
        }
        guard !files.isEmpty else { return .failure(.nothing) }
        // The deepest folder holding every file.
        var common = files[0].deletingLastPathComponent().pathComponents
        for f in files.dropFirst() {
            let c = f.deletingLastPathComponent().pathComponents
            common = Array(zip(common, c).prefix { $0 == $1 }.map(\.0))
        }
        let folder = URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true).standardizedFileURL
        // Inside a folder that was handed over (a loose file's own folder never was).
        guard let root = used.first(where: { isDir($0) && isInside(folder, $0) }) else {
            return .failure(used.count > 1 ? .severalSources : .looseFiles)
        }
        if whole, used == [root] { return .success(Plan(folder: root, only: nil)) }
        let base = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        let rels = Set(files.map { String($0.standardizedFileURL.path.dropFirst(base.count)) })
        return .success(Plan(folder: folder, only: rels))
    }

    enum Refusal: String, Error {
        case nothing = "Nothing shown to open"
        case unknown = "Lumina can't find these files on disk any more: add them again"
        case severalSources = "Pick opens one folder: find within one source first"
        case looseFiles = "Pick opens folders: add the folder these files are in"
    }

    /// A shoot id of its own for part of a folder (`SetsShootStore.isID`'s form), so its decisions never mix with
    /// the whole folder's session; the same part gets the same id again.
    static func subsetID(place: String, only: Set<String>) -> String {
        String(SetsFileOps.sha256(Data((place + "|only|" + only.sorted().joined(separator: "\n")).utf8)).prefix(16))
    }

    /// A listing cut to the files handed over: their sidecars and same-named files (a JPEG beside the RAW) stay.
    static func stems(_ only: Set<String>) -> Set<String> { Set(only.map(stem)) }
    static func stem(_ rel: String) -> String { (rel as NSString).deletingPathExtension.lowercased() }
    /// "DSC00002.xmp", "DSC00002.ARW.xmp" and "DSC00002.JPG" go with "DSC00002.ARW".
    static func isTwin(_ rel: String, of stems: Set<String>) -> Bool { stems.contains(stem(rel)) || stems.contains(stem(stem(rel))) }

    private static func isInside(_ folder: URL, _ root: URL) -> Bool {
        let f = folder.standardizedFileURL.pathComponents, r = root.standardizedFileURL.pathComponents
        return f.count >= r.count && Array(f.prefix(r.count)) == r
    }
    private static func isDir(_ u: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
    }
}
