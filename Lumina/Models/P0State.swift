import Foundation

// MARK: - Schema

/// Versioned P0 shoot persistence schema.
enum ShootSchemaVersion: Int, Codable, Sendable, Comparable {
    case v1 = 1

    static let current: ShootSchemaVersion = .v1

    static func < (lhs: ShootSchemaVersion, rhs: ShootSchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Cull (independent of edit)

enum CullDecision: String, Codable, Hashable, Sendable {
    case undecided
    case keep
    case reject
    case hold

    init(tier: PhotoTier) {
        switch tier {
        case .keep: self = .keep
        case .reject: self = .reject
        case .unranked: self = .undecided
        }
    }

    var asTier: PhotoTier {
        switch self {
        case .keep: return .keep
        case .reject: return .reject
        case .hold, .undecided: return .unranked
        }
    }
}

// MARK: - Source references

enum SourceAvailability: String, Codable, Hashable, Sendable {
    case available
    case missing
    case unknown
}

/// External folder / drive reference with security-scoped bookmark support.
struct SourceReference: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    /// Absolute path when last known.
    var originalPath: String
    /// Security-scoped bookmark bytes when available.
    var bookmarkData: Data?
    /// Path of the asset relative to the shoot root (stable across remounts when volume matches).
    var relativePath: String
    var volumeID: String?
    var availability: SourceAvailability
    var lastSeenAt: Date?

    init(
        id: UUID = UUID(),
        originalPath: String,
        bookmarkData: Data? = nil,
        relativePath: String,
        volumeID: String? = nil,
        availability: SourceAvailability = .unknown,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.originalPath = originalPath
        self.bookmarkData = bookmarkData
        self.relativePath = relativePath
        self.volumeID = volumeID
        self.availability = availability
        self.lastSeenAt = lastSeenAt
    }

    static func make(
        fileURL: URL,
        rootURL: URL,
        bookmarkData: Data? = nil
    ) -> SourceReference {
        let relative = AssetIdentity.relativePath(file: fileURL, root: rootURL)
        let volume = AssetIdentity.volumeIdentifier(for: fileURL)
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        return SourceReference(
            originalPath: fileURL.path,
            bookmarkData: bookmarkData,
            relativePath: relative,
            volumeID: volume,
            availability: exists ? .available : .missing,
            lastSeenAt: exists ? Date() : nil
        )
    }
}

// MARK: - Asset

/// Durable per-photograph catalog record. Missing originals do not delete this.
struct AssetRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// Opaque rediscovery key (volume + relative path + size + capture).
    var sourceKey: String
    var source: SourceReference
    var filename: String
    var cull: CullDecision
    /// Canonical edit recipe. Nil = camera / neutral decode.
    var recipe: EditRecipe?
    var capturedAt: Date?
    var fileSize: Int64?
    /// Cached preview paths keyed by asset identity (not filename stem).
    var thumbPath: String?
    var gridThumbPath: String?
    var proxyPath: String?
    var previewOrigin: PreviewOrigin
    var previewLongEdge: Int

    // Quality / grouping (runtime aids; independent of cull/edit contracts)
    var sharpness: Double
    var exposureHealth: Double
    var faceQuality: Double
    var aesthetic: Double
    var compositeQuality: Double
    var faceDetected: Bool
    var cullScore: Double
    var cullConfidence: Double
    var editConfidence: Double
    var tasteMatch: Double
    var proposedTier: PhotoTier?
    var userDecidedAt: Date?
    var settledAt: Date?
    var isFlagged: Bool
    var isBurstHero: Bool
    var isClusterHero: Bool
    var uncertaintyKind: UncertaintyKind
    var whyUncertain: String?
    var whyAction: String?
    var burstID: String?
    var clusterID: String?
    var clusterLabel: String?
    var embedding: [Float]?

    init(
        id: UUID,
        sourceKey: String,
        source: SourceReference,
        filename: String,
        cull: CullDecision = .undecided,
        recipe: EditRecipe? = nil,
        capturedAt: Date? = nil,
        fileSize: Int64? = nil,
        thumbPath: String? = nil,
        gridThumbPath: String? = nil,
        proxyPath: String? = nil,
        previewOrigin: PreviewOrigin = .unknown,
        previewLongEdge: Int = 0,
        sharpness: Double = 0,
        exposureHealth: Double = 0.5,
        faceQuality: Double = 0,
        aesthetic: Double = 0.5,
        compositeQuality: Double = 0,
        faceDetected: Bool = false,
        cullScore: Double = 0,
        cullConfidence: Double = 0,
        editConfidence: Double = 1,
        tasteMatch: Double = 0.5,
        proposedTier: PhotoTier? = nil,
        userDecidedAt: Date? = nil,
        settledAt: Date? = nil,
        isFlagged: Bool = false,
        isBurstHero: Bool = true,
        isClusterHero: Bool = true,
        uncertaintyKind: UncertaintyKind = .none,
        whyUncertain: String? = nil,
        whyAction: String? = nil,
        burstID: String? = nil,
        clusterID: String? = nil,
        clusterLabel: String? = nil,
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.sourceKey = sourceKey
        self.source = source
        self.filename = filename
        self.cull = cull
        self.recipe = recipe
        self.capturedAt = capturedAt
        self.fileSize = fileSize
        self.thumbPath = thumbPath
        self.gridThumbPath = gridThumbPath
        self.proxyPath = proxyPath
        self.previewOrigin = previewOrigin
        self.previewLongEdge = previewLongEdge
        self.sharpness = sharpness
        self.exposureHealth = exposureHealth
        self.faceQuality = faceQuality
        self.aesthetic = aesthetic
        self.compositeQuality = compositeQuality
        self.faceDetected = faceDetected
        self.cullScore = cullScore
        self.cullConfidence = cullConfidence
        self.editConfidence = editConfidence
        self.tasteMatch = tasteMatch
        self.proposedTier = proposedTier
        self.userDecidedAt = userDecidedAt
        self.settledAt = settledAt
        self.isFlagged = isFlagged
        self.isBurstHero = isBurstHero
        self.isClusterHero = isClusterHero
        self.uncertaintyKind = uncertaintyKind
        self.whyUncertain = whyUncertain
        self.whyAction = whyAction
        self.burstID = burstID
        self.clusterID = clusterID
        self.clusterLabel = clusterLabel
        self.embedding = embedding
    }
}

// MARK: - Final order (independent of discovery order)

struct FinalSetOrder: Codable, Hashable, Sendable {
    /// Kept-set presentation order. Empty means chronological discovery order.
    var assetIDs: [UUID] = []

    var isCustom: Bool { !assetIDs.isEmpty }
}

// MARK: - Batch edit command

/// Exact before/after recipes for every recipient. Geometry excluded by default.
struct BatchEditCommand: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var createdAt: Date
    var leaderAssetID: UUID?
    /// When false (default), crop/straighten from the leader are stripped before apply.
    var includeGeometry: Bool
    var recipients: [BatchEditRecipient]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        leaderAssetID: UUID? = nil,
        includeGeometry: Bool = false,
        recipients: [BatchEditRecipient] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.leaderAssetID = leaderAssetID
        self.includeGeometry = includeGeometry
        self.recipients = recipients
    }

    /// Build a command from a leader recipe applied to recipients.
    /// Geometry is stripped unless `includeGeometry` is true.
    static func make(
        leaderAssetID: UUID,
        leaderRecipe: EditRecipe,
        recipientIDs: [UUID],
        priorRecipes: [UUID: EditRecipe?],
        includeGeometry: Bool = false
    ) -> BatchEditCommand {
        let applied: EditRecipe
        if includeGeometry {
            applied = leaderRecipe.forked()
        } else {
            applied = leaderRecipe.forked().updating {
                $0.crop = nil
                $0.straightenDegrees = 0
            }
        }
        let recipients = recipientIDs.map { id in
            BatchEditRecipient(
                assetID: id,
                before: priorRecipes[id] ?? nil,
                after: applied.forked()
            )
        }
        return BatchEditCommand(
            leaderAssetID: leaderAssetID,
            includeGeometry: includeGeometry,
            recipients: recipients
        )
    }
}

struct BatchEditRecipient: Codable, Hashable, Sendable {
    var assetID: UUID
    var before: EditRecipe?
    var after: EditRecipe
}

// MARK: - Export history (does not redefine kept set)

struct ExportRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var destinationPath: String
    var aspect: ExportAspect
    /// Snapshot of which assets were exported — not the live kept set.
    var exportedAssetIDs: [UUID]
    var collectionName: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        destinationPath: String,
        aspect: ExportAspect,
        exportedAssetIDs: [UUID],
        collectionName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.destinationPath = destinationPath
        self.aspect = aspect
        self.exportedAssetIDs = exportedAssetIDs
        self.collectionName = collectionName
    }
}

// MARK: - Workspace restore

enum WorkspaceScale: String, Codable, Hashable, Sendable {
    case contactSheet
    case singlePhoto
}

/// Durable UI restore — never animation or hover ephemera.
struct WorkspaceRestoreState: Codable, Hashable, Sendable {
    var focusedAssetID: UUID?
    var filter: GridFilter
    /// Approximate contact-sheet density (columns). Nil = default.
    var contactSheetDensity: Int?
    /// Normalized scroll anchor 0…1 within the contact sheet.
    var scrollAnchor: Double?
    var scale: WorkspaceScale
    var keptOrderMode: Bool

    static let `default` = WorkspaceRestoreState(
        focusedAssetID: nil,
        filter: .all,
        contactSheetDensity: nil,
        scrollAnchor: nil,
        scale: .contactSheet,
        keptOrderMode: false
    )

    enum CodingKeys: String, CodingKey {
        case focusedAssetID, filter, contactSheetDensity, scrollAnchor, scale, keptOrderMode
    }

    init(
        focusedAssetID: UUID? = nil,
        filter: GridFilter = .all,
        contactSheetDensity: Int? = nil,
        scrollAnchor: Double? = nil,
        scale: WorkspaceScale = .contactSheet,
        keptOrderMode: Bool = false
    ) {
        self.focusedAssetID = focusedAssetID
        self.filter = filter
        self.contactSheetDensity = contactSheetDensity
        self.scrollAnchor = scrollAnchor
        self.scale = scale
        self.keptOrderMode = keptOrderMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusedAssetID = try c.decodeIfPresent(UUID.self, forKey: .focusedAssetID)
        filter = try c.decodeIfPresent(GridFilter.self, forKey: .filter) ?? .all
        contactSheetDensity = try c.decodeIfPresent(Int.self, forKey: .contactSheetDensity)
        scrollAnchor = try c.decodeIfPresent(Double.self, forKey: .scrollAnchor)
        scale = try c.decodeIfPresent(WorkspaceScale.self, forKey: .scale) ?? .contactSheet
        keptOrderMode = try c.decodeIfPresent(Bool.self, forKey: .keptOrderMode) ?? false
    }
}

// MARK: - Shoot

/// Canonical persisted shoot. Supersedes ad-hoc `LuminaProject` as the on-disk authority.
struct ShootRecord: Codable, Sendable, Identifiable {
    var schemaVersion: ShootSchemaVersion
    var id: UUID
    var name: String
    var createdAt: Date
    var rawFolder: SourceReference?
    var jpgFolder: SourceReference?
    var keepRateTarget: Double
    var jobBrief: JobBrief
    /// Taste baseline — EditRecipe (geometry unused).
    var profile: EditRecipe
    var tasteSourceCount: Int
    var tasteStrength: Double
    var assets: [AssetRecord]
    var finalSetOrder: FinalSetOrder
    var collections: [ExportCollection]
    var exportHistory: [ExportRecord]
    var batchHistory: [BatchEditCommand]
    var decisionLedger: [DecisionEvent]
    var auditSeedPhotoIDs: Set<UUID>
    var workspace: WorkspaceRestoreState

    init(
        schemaVersion: ShootSchemaVersion = .current,
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        rawFolder: SourceReference? = nil,
        jpgFolder: SourceReference? = nil,
        keepRateTarget: Double = 0.10,
        jobBrief: JobBrief = JobBrief(),
        profile: EditRecipe = .neutral,
        tasteSourceCount: Int = 0,
        tasteStrength: Double = 1.0,
        assets: [AssetRecord] = [],
        finalSetOrder: FinalSetOrder = FinalSetOrder(),
        collections: [ExportCollection] = [],
        exportHistory: [ExportRecord] = [],
        batchHistory: [BatchEditCommand] = [],
        decisionLedger: [DecisionEvent] = [],
        auditSeedPhotoIDs: Set<UUID> = [],
        workspace: WorkspaceRestoreState = .default
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.rawFolder = rawFolder
        self.jpgFolder = jpgFolder
        self.keepRateTarget = keepRateTarget
        self.jobBrief = jobBrief
        self.profile = profile
        self.tasteSourceCount = tasteSourceCount
        self.tasteStrength = tasteStrength
        self.assets = assets
        self.finalSetOrder = finalSetOrder
        self.collections = collections
        self.exportHistory = exportHistory
        self.batchHistory = batchHistory
        self.decisionLedger = decisionLedger
        self.auditSeedPhotoIDs = auditSeedPhotoIDs
        self.workspace = workspace
    }
}

// MARK: - Persistence errors (surfaced factually)

enum ShootStoreError: Error, LocalizedError, Equatable {
    case notFound(String)
    case decodeFailed(String)
    case writeFailed(String)
    case migrationFailed(String)
    case bookmarkResolveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let name): return "Shoot not found: \(name)"
        case .decodeFailed(let detail): return "Shoot decode failed: \(detail)"
        case .writeFailed(let detail): return "Shoot write failed: \(detail)"
        case .migrationFailed(let detail): return "Shoot migration failed: \(detail)"
        case .bookmarkResolveFailed(let detail): return "Bookmark resolve failed: \(detail)"
        }
    }
}

struct RecentShootSummary: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var assetCount: Int
    var keepCount: Int
    var lastOpenedAt: Date
    var rawFolderPath: String?
}
