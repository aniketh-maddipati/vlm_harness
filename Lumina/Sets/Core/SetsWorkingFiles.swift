import Foundation

/// Accounts for and removes files in Lumina's Application Support shoot folders.
///
/// The shoot store currently names only `session.json`; no on-disk preview or thumbnail layout is
/// defined there. Inventory therefore calls every other regular file `.other`. Callers that add a
/// cache layout can construct typed items without weakening the deletion guards here.
nonisolated struct SetsWorkingFiles {
    enum Kind: Equatable, Sendable {
        case preview
        case thumb
        case session
        case other
    }

    struct Item: Sendable {
        let url: URL
        let bytes: Int64
        let modified: Date
        let shoot: String
        let kind: Kind
        let protected: Bool

        /// The boundary and current-shoot bit travel with an item so `apply` cannot be handed an
        /// unbounded URL, and `plan` can preserve the required cross-shoot ordering.
        fileprivate let root: URL
        fileprivate let isCurrent: Bool

        init(
            url: URL,
            bytes: Int64,
            modified: Date,
            shoot: String,
            kind: Kind,
            protected: Bool,
            root: URL,
            isCurrent: Bool
        ) {
            self.url = url
            self.bytes = max(0, bytes)
            self.modified = modified
            self.shoot = shoot
            self.kind = kind
            self.protected = protected
            self.root = root
            self.isCurrent = isCurrent
        }
    }

    struct Plan: Sendable {
        let remove: [Item]
        let after: Int64
        let metCap: Bool
    }

    struct SafetyViolation: Error, Equatable, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// Formats that can be originals, handoff files, or user-visible image files. Working-file
    /// removal refuses all of them even when one appears below Application Support.
    static let deniedExtensions: Set<String> = [
        "arw", "dng", "raw", "cr2", "cr3", "nef", "nrw", "orf", "raf", "rw2", "pef", "srw",
        "xmp", "jpg", "jpeg", "heic", "heif", "tif", "tiff",
    ]

    static func bytes(of dir: URL) -> Int64 {
        regularFiles(in: dir).reduce(0) { total, entry in
            adding(total, entry.bytes)
        }
    }

    static func inventory(root: URL, current: String?, picks: Set<String>) -> [Item] {
        regularFiles(in: root).compactMap { entry in
            guard let relative = relativePath(of: entry.url, under: root),
                  let shoot = relative.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init)
            else { return nil }

            let inShoot = String(relative.dropFirst(min(relative.count, shoot.count + 1)))
            let kind: Kind = entry.url.lastPathComponent == "session.json" ? .session : .other
            let isCurrent = shoot == current
            let isPick = picks.contains(inShoot) || picks.contains(entry.url.lastPathComponent)
            return Item(
                url: entry.url,
                bytes: entry.bytes,
                modified: entry.modified,
                shoot: shoot,
                kind: kind,
                protected: kind == .session || (kind == .preview && isCurrent && isPick),
                root: root,
                isCurrent: isCurrent
            )
        }
    }

    static func plan(items: [Item], cap: Int64?) -> Plan {
        let total = items.reduce(Int64(0)) { adding($0, $1.bytes) }
        guard let cap else { return Plan(remove: [], after: total, metCap: true) }
        let target = max(0, cap)
        guard total > target else { return Plan(remove: [], after: total, metCap: true) }

        let candidates = items.filter {
            $0.kind == .preview && !$0.protected
        }.sorted {
            if $0.isCurrent != $1.isCurrent { return !$0.isCurrent }
            if $0.modified != $1.modified { return $0.modified < $1.modified }
            return $0.url.path < $1.url.path
        }

        var after = total
        var remove: [Item] = []
        for item in candidates where after > target {
            remove.append(item)
            after = max(0, after - item.bytes)
        }
        return Plan(remove: remove, after: after, metCap: after <= target)
    }

    static func removeAll(shootDir: URL, keepSession: Bool) throws -> Int64 {
        let entries = allEntries(in: shootDir)
        let files = entries.filter { $0.type == .typeRegular || $0.type == .typeSymbolicLink }
        let toRemove = files.filter {
            !(keepSession && $0.url.lastPathComponent == "session.json" && $0.type == .typeRegular)
        }

        try toRemove.forEach { try validateDeletion(of: $0.url, root: shootDir) }

        var freed: Int64 = 0
        for entry in toRemove {
            try FileManager.default.removeItem(at: entry.url)
            if entry.type == .typeRegular { freed = adding(freed, entry.bytes) }
        }

        // Remove only directories that became empty. The shoot directory itself remains as the
        // caller's boundary, including when no session was kept.
        for entry in entries.reversed() where entry.type == .typeDirectory {
            try? FileManager.default.removeItem(at: entry.url)
        }
        return freed
    }

    static func apply(_ plan: Plan) throws -> (freed: Int64, failed: [URL]) {
        // Validate the whole set first: a safety violation must delete nothing.
        try plan.remove.forEach { try validateDeletion(of: $0.url, root: $0.root) }

        var freed: Int64 = 0
        var failed: [URL] = []
        for item in plan.remove {
            do {
                try FileManager.default.removeItem(at: item.url)
                freed = adding(freed, item.bytes)
            } catch {
                failed.append(item.url)
            }
        }
        return (freed, failed)
    }

    private struct Entry {
        let url: URL
        let bytes: Int64
        let modified: Date
        let type: FileAttributeType
    }

    /// Uses lstat-style attributes and skips descendants of links, so neither accounting nor
    /// inventory can escape through a symlink.
    private static func allEntries(in root: URL) -> [Entry] {
        var result: [Entry] = []
        func visit(_ directory: URL) {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: []
            )) ?? []
            for url in children {
                let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
                    || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let reportedType = attributes[.type] as? FileAttributeType
                else { continue }
                let type: FileAttributeType = isLink ? .typeSymbolicLink : reportedType
                let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                let modified = attributes[.modificationDate] as? Date ?? .distantPast
                result.append(Entry(url: url, bytes: max(0, bytes), modified: modified, type: type))
                if type == .typeDirectory { visit(url) }
            }
        }
        visit(root)
        return result
    }

    private static func regularFiles(in root: URL) -> [Entry] {
        allEntries(in: root).filter { entry in
            guard entry.type == .typeRegular else { return false }
            let resolvedRoot = canonical(root)
            let resolvedFile = canonical(entry.url)
            return contains(resolvedFile, in: resolvedRoot)
        }
    }

    private static func validateDeletion(of url: URL, root: URL) throws {
        let resolvedRoot = canonical(root)
        let resolvedURL = canonical(url)
        guard contains(resolvedURL, in: resolvedRoot) else {
            throw SafetyViolation(message: "working file is outside its root")
        }
        let name = url.lastPathComponent.lowercased()
        guard !name.hasSuffix(".lumina-bak") else {
            throw SafetyViolation(message: "backup files are never working files")
        }
        guard !deniedExtensions.contains(url.pathExtension.lowercased()) else {
            throw SafetyViolation(message: "photo and sidecar files are never working files")
        }
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func contains(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.path == "/" ? "/" : root.path + "/"
        return url.path.hasPrefix(rootPath) && url.path != root.path
    }

    private static func relativePath(of url: URL, under root: URL) -> String? {
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = base == "/" ? "/" : base + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    private static func adding(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : sum
    }
}
