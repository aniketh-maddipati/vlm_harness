import Foundation

/// Actor-backed shoot persistence boundary.
/// Serialized writes, atomic temp replacement, schema version, recoverable last-known-good.
/// File IO helpers are nonisolated; the actor serializes debounced writes per shoot.
actor ShootStore {
    static let shared = ShootStore()

    private var pendingSaves: [String: Task<Void, Never>] = [:]
    private var lastError: [String: String] = [:]

    // MARK: - Paths (nonisolated)

    nonisolated static func supportDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumina", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    nonisolated static func shootDirectory(for name: String) throws -> URL {
        let dir = try supportDirectory().appendingPathComponent("projects/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func shootJSONURL(for name: String) throws -> URL {
        try shootDirectory(for: name).appendingPathComponent("shoot.json")
    }

    nonisolated static func legacyProjectJSONURL(for name: String) throws -> URL {
        try shootDirectory(for: name).appendingPathComponent("project.json")
    }

    nonisolated static func goodCopyURL(for name: String) throws -> URL {
        try shootDirectory(for: name).appendingPathComponent("shoot.json.good")
    }

    nonisolated static func cacheDirectory(for shootName: String, tier: String) throws -> URL {
        let dir = try shootDirectory(for: shootName)
            .appendingPathComponent("cache/\(tier)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func cacheFileURL(shootName: String, tier: String, assetID: UUID) throws -> URL {
        try cacheDirectory(for: shootName, tier: tier)
            .appendingPathComponent(AssetIdentity.cacheStem(for: assetID) + ".jpg")
    }

    nonisolated func supportDirectory() throws -> URL { try Self.supportDirectory() }
    nonisolated func shootDirectory(for name: String) throws -> URL { try Self.shootDirectory(for: name) }
    nonisolated func shootJSONURL(for name: String) throws -> URL { try Self.shootJSONURL(for: name) }
    nonisolated func cacheDirectory(for shootName: String, tier: String) throws -> URL {
        try Self.cacheDirectory(for: shootName, tier: tier)
    }
    nonisolated func cacheFileURL(shootName: String, tier: String, assetID: UUID) throws -> URL {
        try Self.cacheFileURL(shootName: shootName, tier: tier, assetID: assetID)
    }

    // MARK: - Load / save (nonisolated IO)

    nonisolated static func loadShoot(id name: String) throws -> ShootRecord {
        let primary = try shootJSONURL(for: name)
        let legacy = try legacyProjectJSONURL(for: name)
        let good = try goodCopyURL(for: name)

        if FileManager.default.fileExists(atPath: primary.path) {
            do {
                let data = try Data(contentsOf: primary)
                return try ShootMigration.decodeShoot(from: data)
            } catch {
                if FileManager.default.fileExists(atPath: good.path) {
                    let data = try Data(contentsOf: good)
                    return try ShootMigration.decodeShoot(from: data)
                }
                throw ShootStoreError.decodeFailed(error.localizedDescription)
            }
        }

        if FileManager.default.fileExists(atPath: legacy.path) {
            let data = try Data(contentsOf: legacy)
            return try ShootMigration.decodeShoot(from: data)
        }

        if FileManager.default.fileExists(atPath: good.path) {
            let data = try Data(contentsOf: good)
            return try ShootMigration.decodeShoot(from: data)
        }

        throw ShootStoreError.notFound(name)
    }

    nonisolated static func saveShoot(_ shoot: ShootRecord) throws {
        try writeAtomically(shoot)
        try rememberLastOpened(name: shoot.name, id: shoot.id)
    }

    nonisolated static func listRecentShoots() throws -> [RecentShootSummary] {
        let root = try supportDirectory().appendingPathComponent("projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var summaries: [RecentShootSummary] = []
        for dir in contents where dir.hasDirectoryPath {
            let name = dir.lastPathComponent
            guard let shoot = try? loadShoot(id: name) else { continue }
            let mod = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))
                .flatMap(\.contentModificationDate) ?? shoot.createdAt
            summaries.append(
                RecentShootSummary(
                    id: shoot.id,
                    name: shoot.name,
                    assetCount: shoot.assets.count,
                    keepCount: shoot.assets.filter { $0.cull == .keep }.count,
                    lastOpenedAt: mod,
                    rawFolderPath: shoot.rawFolder?.originalPath
                )
            )
        }
        return summaries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    nonisolated static func createOrOpenShoot(from folderURL: URL, name: String? = nil) throws -> ShootRecord {
        let shootName = name ?? folderURL.lastPathComponent
        if let existing = try? loadShoot(id: shootName) {
            let refreshed = refreshAvailability(existing, folderURL: folderURL)
            try saveShoot(refreshed)
            return refreshed
        }

        var rawRef = SourceReference(
            originalPath: folderURL.path,
            relativePath: "",
            volumeID: AssetIdentity.volumeIdentifier(for: folderURL),
            availability: FileManager.default.fileExists(atPath: folderURL.path) ? .available : .missing,
            lastSeenAt: Date()
        )
        if let data = try? folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            rawRef.bookmarkData = data
        }

        let shoot = ShootRecord(name: shootName, rawFolder: rawRef)
        try saveShoot(shoot)
        return shoot
    }

    nonisolated static func lastOpenedShootName() -> String? {
        let url = try? supportDirectory().appendingPathComponent("last_project.txt")
        guard let url,
              let name = try? String(contentsOf: url, encoding: .utf8),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Actor API

    func loadShoot(id name: String) throws -> ShootRecord {
        try Self.loadShoot(id: name)
    }

    func saveShoot(_ shoot: ShootRecord) throws {
        do {
            try Self.saveShoot(shoot)
            lastError.removeValue(forKey: shoot.name)
        } catch {
            lastError[shoot.name] = error.localizedDescription
            throw error
        }
    }

    /// Per-shoot debounced save — never shares one global work item across shoots.
    func saveShootDebounced(_ shoot: ShootRecord, delayNanoseconds: UInt64 = 500_000_000) {
        let name = shoot.name
        pendingSaves[name]?.cancel()
        let snapshot = shoot
        pendingSaves[name] = Task {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            do {
                try Self.saveShoot(snapshot)
                lastError.removeValue(forKey: name)
            } catch {
                lastError[name] = error.localizedDescription
            }
            pendingSaves[name] = nil
        }
    }

    func listRecentShoots() throws -> [RecentShootSummary] {
        try Self.listRecentShoots()
    }

    func createOrOpenShoot(from folderURL: URL, name: String? = nil) throws -> ShootRecord {
        try Self.createOrOpenShoot(from: folderURL, name: name)
    }

    func lastPersistenceError(for name: String) -> String? {
        lastError[name]
    }

    func lastOpenedShootName() -> String? {
        Self.lastOpenedShootName()
    }

    // MARK: - Internals

    nonisolated private static func writeAtomically(_ shoot: ShootRecord) throws {
        let dir = try shootDirectory(for: shoot.name)
        let finalURL = try shootJSONURL(for: shoot.name)
        let goodURL = try goodCopyURL(for: shoot.name)
        let tempURL = dir.appendingPathComponent("shoot.json.tmp-\(UUID().uuidString)")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(shoot)
        } catch {
            throw ShootStoreError.writeFailed(error.localizedDescription)
        }

        do {
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try? FileManager.default.removeItem(at: goodURL)
                try? FileManager.default.copyItem(at: finalURL, to: goodURL)
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
            try? FileManager.default.removeItem(at: goodURL)
            try? FileManager.default.copyItem(at: finalURL, to: goodURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw ShootStoreError.writeFailed(error.localizedDescription)
        }
    }

    nonisolated private static func rememberLastOpened(name: String, id: UUID) throws {
        let url = try supportDirectory().appendingPathComponent("last_project.txt")
        try name.write(to: url, atomically: true, encoding: .utf8)
        let idURL = try supportDirectory().appendingPathComponent("last_shoot_id.txt")
        try id.uuidString.write(to: idURL, atomically: true, encoding: .utf8)
    }

    nonisolated private static func refreshAvailability(_ shoot: ShootRecord, folderURL: URL) -> ShootRecord {
        var copy = shoot
        let folderExists = FileManager.default.fileExists(atPath: folderURL.path)
        if var raw = copy.rawFolder {
            raw.originalPath = folderURL.path
            raw.availability = folderExists ? .available : .missing
            raw.lastSeenAt = folderExists ? Date() : raw.lastSeenAt
            copy.rawFolder = raw
        }
        copy.assets = copy.assets.map { asset in
            var a = asset
            if folderExists {
                let path = folderURL.appendingPathComponent(asset.source.relativePath).path
                if !asset.source.relativePath.isEmpty, FileManager.default.fileExists(atPath: path) {
                    a.source.originalPath = path
                    a.source.availability = .available
                    a.source.lastSeenAt = Date()
                } else if FileManager.default.fileExists(atPath: asset.source.originalPath) {
                    a.source.availability = .available
                } else {
                    a.source.availability = .missing
                }
            } else {
                a.source.availability = .missing
            }
            return a
        }
        return copy
    }
}
