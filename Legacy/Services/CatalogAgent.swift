// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import Foundation

/// Scans backlog roots, runs L1 index passes, and picks the next folder to cull.
enum CatalogAgent {
    private static let indexConcurrency = 2

    static func loadSavedQueue() async -> CatalogQueueState? {
        guard let root = await CatalogStore.shared.loadRootPath() else { return nil }
        let folders = (try? await CatalogStore.shared.allFolders()) ?? []
        guard !folders.isEmpty else { return nil }
        let brief = await CatalogStore.shared.loadBrief() ?? JobBrief()
        return CatalogQueueState(rootPath: root, brief: brief, folders: folders)
    }

    static func scan(root: URL, brief: JobBrief) async throws -> CatalogQueueState {
        let shootURLs = CatalogDiscovery.shootFolders(at: root)
        guard !shootURLs.isEmpty else {
            throw CatalogAgentError.noShootFolders
        }

        var folders: [CatalogFolder] = []
        for (rank, url) in shootURLs.enumerated() {
            let projectName = CatalogDiscovery.projectName(for: url)
            var folder = CatalogFolder(
                path: url.path,
                name: url.lastPathComponent,
                projectName: projectName,
                queueRank: rank
            )
            if let existing = try? ProjectStore.load(name: projectName) {
                let stats = folderStats(from: existing)
                folder.status = .indexed
                folder.photoCount = stats.photoCount
                folder.needsYouCount = stats.needsYou
                folder.keepCount = stats.keepCount
                folder.setCount = stats.setCount
                folder.indexedAt = existing.createdAt
            }
            folders.append(folder)
        }

        try await CatalogStore.shared.clearAll()
        try await CatalogStore.shared.saveRootPath(root.path)
        try await CatalogStore.shared.saveBrief(brief)
        try await CatalogStore.shared.upsertFolders(folders)

        return CatalogQueueState(rootPath: root.path, brief: brief, folders: folders)
    }

    static func indexFolder(_ folder: CatalogFolder, keepRate: Double) async throws -> LuminaProject {
        if folder.status == .indexed || folder.status == .active {
            if let saved = try? ProjectStore.load(name: folder.projectName) {
                return saved
            }
        }

        try await CatalogStore.shared.updateStatus(id: folder.id, status: .indexing)
        do {
            let project = try await ImportPipeline.indexLightweight(
                sourceFolder: folder.url,
                projectName: folder.projectName,
                keepRate: keepRate
            )
            let stats = folderStats(from: project)
            try await CatalogStore.shared.updateStats(
                id: folder.id,
                photoCount: stats.photoCount,
                needsYouCount: stats.needsYou,
                keepCount: stats.keepCount,
                setCount: stats.setCount,
                status: .indexed
            )
            try await CatalogStore.shared.execIndexedAt(id: folder.id)
            return project
        } catch {
            try await CatalogStore.shared.updateStatus(
                id: folder.id,
                status: .error,
                error: error.localizedDescription
            )
            throw error
        }
    }

    /// Background L1 indexing for pending folders while user culls.
    static func runBackgroundIndexing(
        folders: [CatalogFolder],
        keepRate: Double,
        onUpdate: @Sendable @escaping (UUID, CatalogFolderStatus, String?) async -> Void
    ) async {
        let pending = folders.filter { $0.status == .pending }
        guard !pending.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<min(indexConcurrency, pending.count) {
                guard let next = iterator.next() else { break }
                group.addTask {
                    await indexOne(next, keepRate: keepRate, onUpdate: onUpdate)
                }
            }
            while let next = iterator.next() {
                await group.next()
                group.addTask {
                    await indexOne(next, keepRate: keepRate, onUpdate: onUpdate)
                }
            }
        }
    }

    static func nextWorkItem(in folders: [CatalogFolder]) -> CatalogFolder? {
        if let active = folders.first(where: { $0.status == .active }) { return active }
        let open = folders.filter { $0.status != .cleared && $0.status != .error }
        if let urgent = open.first(where: { $0.status == .indexed && $0.needsYouCount > 0 }) {
            return urgent
        }
        if let ready = open.first(where: { $0.status == .indexed }) { return ready }
        if let indexing = open.first(where: { $0.status == .indexing }) { return indexing }
        return open.first(where: { $0.status == .pending })
    }

    static func planText(for state: CatalogQueueState) -> String {
        let photos = state.folders.reduce(0) { $0 + $1.photoCount }
        let needsYou = state.folders.reduce(0) { $0 + $1.needsYouCount }
        let rate = state.brief.resolvedKeepRate(totalPhotos: max(photos, 1))
        let target = Int((Double(photos) * rate).rounded())
        return "Backlog: \(state.totalFolders) folders · ~\(target) keeps · \(needsYou) need you · \(state.clearedCount) done"
    }

    static func folderStats(from project: LuminaProject) -> (photoCount: Int, needsYou: Int, keepCount: Int, setCount: Int) {
        let photos = project.photos
        let accepted = project.decisionLedger.reduce(into: [AuditReason: Set<PhotoID>]()) { result, event in
            guard event.kind == .pileAccepted else { return }
            result[event.reason, default: []].formUnion(event.photoIDs)
        }
        let unresolvedAuditCount = photos.reduce(into: 0) { count, photo in
            guard let reason = photo.auditReason,
                  accepted[reason]?.contains(photo.id) != true else { return }
            count += 1
        }
        return (
            photoCount: photos.count,
            needsYou: unresolvedAuditCount,
            keepCount: photos.filter { $0.tier == .keep }.count,
            setCount: Set(photos.compactMap(\.clusterID)).count
        )
    }

    static func syncStats(for folderID: UUID, project: LuminaProject) async {
        let stats = folderStats(from: project)
        try? await CatalogStore.shared.updateStats(
            id: folderID,
            photoCount: stats.photoCount,
            needsYouCount: stats.needsYou,
            keepCount: stats.keepCount,
            setCount: stats.setCount
        )
    }

    // MARK: - Private

    private static func indexOne(
        _ folder: CatalogFolder,
        keepRate: Double,
        onUpdate: @Sendable @escaping (UUID, CatalogFolderStatus, String?) async -> Void
    ) async {
        await onUpdate(folder.id, .indexing, nil)
        do {
            _ = try await indexFolder(folder, keepRate: keepRate)
            await onUpdate(folder.id, .indexed, nil)
        } catch {
            await onUpdate(folder.id, .error, error.localizedDescription)
        }
    }
}

enum CatalogAgentError: LocalizedError {
    case noShootFolders

    var errorDescription: String? {
        switch self {
        case .noShootFolders: "No shoot folders with photos found under that root."
        }
    }
}
