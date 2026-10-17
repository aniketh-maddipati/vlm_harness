import Foundation

/// Where Skim's Final Cut file and cut list go (Export ▸ Save to). One folder the user chose with the folder panel,
/// kept as a security-scoped bookmark in `skim/export.json` in the container, or none: then each save asks with the
/// save panel. The page never names a place; it only sees the folder's path to show it. A save never replaces a
/// file: a name that is taken gets " 2", " 3", … before its extension. What was written is read back before it
/// counts as saved. Foundation only (the panels live in SetsBridge).
nonisolated struct SkimExport: Sendable {
    /// The chosen folder: its bookmark and the path it had when chosen (shown until the bookmark resolves).
    struct Place: Codable, Equatable, Sendable {
        var bookmark: Data
        var path: String
    }

    /// One save's answer to the page.
    struct Saved: Equatable, Sendable {
        var ok: Bool
        var path: String
        var why: String
        var json: [String: Any] { ok ? ["ok": true, "path": path, "name": (path as NSString).lastPathComponent, "folder": (path as NSString).deletingLastPathComponent] : ["ok": false, "why": why] }
    }

    /// What the page may save: a Final Cut file or a plain-text list, at most 16 MB (a 5,000-clip .fcpxml is about 3 MB).
    static let extensions: Set<String> = ["fcpxml", "txt"]
    static let maxBytes = 16 << 20

    let file: URL

    func place() -> Place? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Place.self, from: data)
    }

    /// Keeps the folder, or forgets it (nil: ask each time).
    @discardableResult
    func set(_ p: Place?) -> Bool {
        do {
            guard let p else { if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }; return true }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(p).write(to: file, options: .atomic)
            return true
        } catch { return false }
    }

    /// The page's suggested name as one plain file name with an extension Skim writes: no folders, no leading dot,
    /// no control characters or colons, at most 128 characters. Nil when nothing is left or the extension is not one
    /// of `allowed` (`extensions`; a matte is a .mov, `SkimFollow.matteName`).
    static func safeName(_ suggested: String, allowed: Set<String> = extensions) -> String? {
        if suggested.hasSuffix("/") || suggested.hasSuffix("\\") { return nil }   // a folder, not a file
        let last = suggested.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var name = String(String.UnicodeScalarView(last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" }))
        while let f = name.first, f == "." || f.isWhitespace { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespaces)
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        guard allowed.contains(ext.lowercased()), !stem.isEmpty else { return nil }
        return String(stem.prefix(120)) + "." + ext
    }

    /// The first free name in `dir`: the name itself, then "name 2.ext", "name 3.ext", … (up to 999).
    static func free(in dir: URL, name: String) -> URL? {
        let fm = FileManager.default, stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        for n in 1...999 {
            let u = dir.appendingPathComponent(n == 1 ? name : "\(stem) \(n).\(ext)")
            if !fm.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// Writes `text` as a new file at `to` (never over one that is there), then reads it back. A file that does not
    /// read back as written is removed and the save fails.
    static func write(_ text: String, to: URL) -> Saved {
        let data = Data(text.utf8)
        guard data.count <= maxBytes else { return Saved(ok: false, path: "", why: "The file is too big to save (\(data.count / 1_048_576) MB).") }
        do {
            try data.write(to: to, options: .withoutOverwriting)
        } catch let e as CocoaError where e.code == .fileWriteFileExists {
            return Saved(ok: false, path: "", why: "A file with that name is already there.")
        } catch let e as CocoaError where e.code == .fileWriteOutOfSpace {
            return Saved(ok: false, path: "", why: "The drive is full.")
        } catch let e as CocoaError where e.code == .fileWriteNoPermission || e.code == .fileWriteVolumeReadOnly {
            return Saved(ok: false, path: "", why: "Lumina may not write in that folder. Choose it again under Save to.")
        } catch {
            return Saved(ok: false, path: "", why: "It could not be saved there.")
        }
        guard (try? Data(contentsOf: to)) == data else {
            try? FileManager.default.removeItem(at: to)
            return Saved(ok: false, path: "", why: "The file did not read back as written, so it was removed.")
        }
        return Saved(ok: true, path: to.path, why: "")
    }

    /// Saves into the chosen folder under the first free name.
    static func save(_ text: String, name: String, into dir: URL) -> Saved {
        guard let clean = safeName(name) else { return Saved(ok: false, path: "", why: "That is not a file name Lumina saves.") }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return Saved(ok: false, path: "", why: "The folder is not there any more. Choose another under Save to.") }
        guard let to = free(in: dir, name: clean) else { return Saved(ok: false, path: "", why: "Too many files with that name in the folder.") }
        return write(text, to: to)
    }

    /// The background check of a .fcpxml before and after it is saved (Export ▸ What you download): which of the clip files
    /// it points at are not on disk, and whether it is valid against Final Cut's own DTD for its version.
    struct Check: Equatable, Sendable {
        /// Files the .fcpxml points at that are not there.
        var missing: [String]
        /// Files Lumina may not look at from here (outside the folder the shoot was opened from), so not checked.
        var unchecked: Int
        /// "ok", "bad" (with `errors`) or "none" (no Final Cut on this Mac, or a version it has no DTD for).
        var dtd: String
        var errors: [String]
        var json: [String: Any] { ["missing": missing, "unchecked": unchecked, "dtd": dtd, "errors": errors] }
    }

    /// The clip files a .fcpxml points at: every `media-rep` src (or an asset's own src), as paths.
    static func mediaPaths(_ text: String) -> [String] {
        var out: [String] = [], seen = Set<String>()
        var rest = Substring(text)
        while let r = rest.range(of: "src=\"") {
            rest = rest[r.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { break }
            let raw = String(rest[..<end]).replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            rest = rest[end...]
            guard let u = URL(string: raw), u.isFileURL else { continue }
            let p = u.path
            if !p.isEmpty, seen.insert(p).inserted { out.append(p) }
        }
        return out
    }

    /// Which of `paths` are missing. Only paths inside `inside` are looked at (the sandbox answers "not there" for any other);
    /// the rest are counted as unchecked rather than guessed.
    static func missing(_ paths: [String], inside: URL?) -> (missing: [String], unchecked: Int) {
        guard let inside else { return ([], paths.count) }
        let base = inside.standardizedFileURL.path, pre = base.hasSuffix("/") ? base : base + "/"
        var miss: [String] = [], un = 0
        for p in paths {
            let std = URL(fileURLWithPath: p).standardizedFileURL.path
            guard std.hasPrefix(pre) else { un += 1; continue }
            if !FileManager.default.fileExists(atPath: std) { miss.append(p) }
        }
        return (miss, un)
    }

    /// Final Cut's DTD for an fcpxml version, inside its app ("1.10" → FCPXMLv1_10.dtd).
    static func dtd(in app: URL, version: String) -> URL? {
        guard version.range(of: "^[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else { return nil }
        let u = app.appendingPathComponent("Contents/Frameworks/Interchange.framework/Versions/A/Resources/FCPXMLv\(version.replacingOccurrences(of: ".", with: "_")).dtd")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// The text against Final Cut's DTD: "ok", "bad" with the first errors, or "none" when there is no DTD to check with.
    static func validate(_ text: String, finalCut app: URL?) -> (dtd: String, errors: [String]) {
        #if os(macOS)
        let version = text.range(of: "<fcpxml version=\"([0-9.]+)\"", options: .regularExpression).map { String(text[$0]).replacingOccurrences(of: "<fcpxml version=\"", with: "").replacingOccurrences(of: "\"", with: "") } ?? ""
        guard let app, let dtdURL = dtd(in: app, version: version) else { return ("none", []) }
        do {
            let doc = try XMLDocument(xmlString: text, options: [])
            let dtd = try XMLDTD(contentsOf: dtdURL, options: [])
            dtd.name = "fcpxml"
            doc.dtd = dtd
            try doc.validate()
            return ("ok", [])
        } catch {
            return ("bad", [String((error as NSError).localizedDescription.prefix(300))])
        }
        #else
        return ("none", [])
        #endif
    }
}
