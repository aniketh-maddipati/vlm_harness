import Foundation

enum CatalogFolderStatus: String, Codable, CaseIterable {
    case pending
    case indexing
    case indexed
    case active
    case cleared
    case error

    var label: String {
        switch self {
        case .pending: "Queued"
        case .indexing: "Indexing…"
        case .indexed: "Ready"
        case .active: "In progress"
        case .cleared: "Done"
        case .error: "Error"
        }
    }
}

struct CatalogFolder: Identifiable, Codable, Equatable {
    var id: UUID
    var path: String
    var name: String
    var projectName: String
    var status: CatalogFolderStatus
    var photoCount: Int
    var needsYouCount: Int
    var keepCount: Int
    var setCount: Int
    var queueRank: Int
    var errorMessage: String?
    var indexedAt: Date?
    var clearedAt: Date?

    var url: URL { URL(fileURLWithPath: path) }

    init(
        id: UUID = UUID(),
        path: String,
        name: String,
        projectName: String,
        status: CatalogFolderStatus = .pending,
        photoCount: Int = 0,
        needsYouCount: Int = 0,
        keepCount: Int = 0,
        setCount: Int = 0,
        queueRank: Int = 0,
        errorMessage: String? = nil,
        indexedAt: Date? = nil,
        clearedAt: Date? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.projectName = projectName
        self.status = status
        self.photoCount = photoCount
        self.needsYouCount = needsYouCount
        self.keepCount = keepCount
        self.setCount = setCount
        self.queueRank = queueRank
        self.errorMessage = errorMessage
        self.indexedAt = indexedAt
        self.clearedAt = clearedAt
    }
}

struct CatalogQueueState: Equatable {
    var rootPath: String?
    var brief: JobBrief = JobBrief()
    var folders: [CatalogFolder] = []
    var activeFolderID: UUID?
    var indexingFolderID: UUID?
    var isScanning = false
    var isIndexing = false

    var totalFolders: Int { folders.count }
    var clearedCount: Int { folders.filter { $0.status == .cleared }.count }
    var readyCount: Int { folders.filter { $0.status == .indexed || $0.status == .active }.count }
    var pendingIndexCount: Int { folders.filter { $0.status == .pending || $0.status == .indexing }.count }

    var activeFolder: CatalogFolder? {
        guard let activeFolderID else { return nil }
        return folders.first { $0.id == activeFolderID }
    }

    var activeFolderIndex: Int? {
        guard let activeFolderID else { return nil }
        return folders.firstIndex { $0.id == activeFolderID }
    }

    var headline: String {
        guard !folders.isEmpty else { return "No backlog loaded" }
        let done = clearedCount
        let total = totalFolders
        if let active = activeFolder {
            if active.needsYouCount > 0 {
                return "Folder \( (activeFolderIndex ?? 0) + 1)/\(total) · \(active.name) · \(active.needsYouCount) need you"
            }
            return "Folder \( (activeFolderIndex ?? 0) + 1)/\(total) · \(active.name)"
        }
        if pendingIndexCount > 0 {
            return "\(readyCount) ready · \(pendingIndexCount) indexing · \(total) folders"
        }
        return "\(done)/\(total) cleared · \(readyCount) ready"
    }

    var agentPlan: String {
        let uncertain = folders.reduce(0) { $0 + $1.needsYouCount }
        let photos = folders.reduce(0) { $0 + $1.photoCount }
        return "Backlog: \(totalFolders) folders · \(photos) photos · \(uncertain) need you · \(clearedCount) done"
    }
}

enum CatalogDiscovery {
    /// Immediate child directories that contain importable photos; falls back to root.
    static func shootFolders(at root: URL, maxDepth: Int = 4) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return [] }

        guard let children = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var folders: [URL] = []
        for child in children {
            let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard childIsDir else { continue }
            let name = child.lastPathComponent.lowercased()
            if name.hasPrefix(".") || name == "node_modules" { continue }
            let count = MediaFormats.discoverPhotos(at: child, maxDepth: maxDepth).importable.count
            if count > 0 { folders.append(child) }
        }

        if folders.isEmpty {
            let rootCount = MediaFormats.discoverPhotos(at: root, maxDepth: maxDepth).importable.count
            if rootCount > 0 { folders.append(root) }
        }

        return folders.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    static func projectName(for folderURL: URL) -> String {
        let base = folderURL.lastPathComponent
        let slug = String(abs(folderURL.path.hashValue), radix: 36)
        return "\(base)-\(slug)"
    }
}
