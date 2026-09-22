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

nonisolated enum CullDecision: String, Codable, Hashable, Sendable {
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

// MARK: - Recipe provenance (independent of CullDecision)

/// Where `AssetRecord.recipe` currently comes from. Named `RecipeSource` (not `source`,
/// which is already `AssetRecord.source: SourceReference` — the file/volume reference).
nonisolated enum RecipeSource: String, Codable, Hashable, Sendable {
    /// Identity `EditRecipe` — camera / neutral decode, nothing chosen yet.
    case shot
    /// Engine-produced recipe (`AutoDevelop`), untouched since.
    case auto
    /// A vision model's proposal, bounded by the engine (`ModelAutoDevelop`), untouched
    /// since. Distinct from `.auto` because it is not reproducible from stats alone.
    case model
    /// An auto recipe the photographer has since nudged by hand.
    case autoHand
    /// Hand-authored from `.shot`, never touched `.auto`.
    case hand
    /// Loaded from an XMP sidecar — the durable receipt is the truth for this asset right now.
    case sidecar
}

// MARK: - Source references

nonisolated enum SourceAvailability: String, Codable, Hashable, Sendable {
    case available
    case missing
    case unknown
}

/// External folder / drive reference with security-scoped bookmark support.
nonisolated struct SourceReference: Codable, Hashable, Sendable, Identifiable {
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
nonisolated struct AssetRecord: Identifiable, Codable, Hashable, Sendable {
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
    /// Where `recipe` currently comes from. Defaults to `.shot` for a fresh/identity recipe.
    var recipeSource: RecipeSource
    /// Last hand-authored recipe, kept when the user switches to shot/auto so returning
    /// to "yours" restores it without re-deriving anything.
    var handRecipe: EditRecipe?
    /// Cached measurements behind the auto pass. Derived, never authoritative —
    /// safe to drop and recompute from the original at any time.
    var imageStats: ImageStats?

    private enum CodingKeys: String, CodingKey {
        case id, sourceKey, source, filename, cull, recipe, capturedAt, fileSize,
             thumbPath, gridThumbPath, proxyPath, previewOrigin, previewLongEdge,
             sharpness, exposureHealth, faceQuality, aesthetic, compositeQuality,
             faceDetected, cullScore, cullConfidence, editConfidence, tasteMatch,
             proposedTier, userDecidedAt, settledAt, isFlagged, isBurstHero, isClusterHero,
             uncertaintyKind, whyUncertain, whyAction, burstID, clusterID, clusterLabel,
             embedding, recipeSource, handRecipe, imageStats
    }

    /// Tolerant decode: `recipeSource` and `handRecipe` post-date every on-disk catalog
    /// written before them, so both fall back to their fresh-record defaults when absent.
    /// Every other field has always been part of the schema and decodes as required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceKey = try c.decode(String.self, forKey: .sourceKey)
        source = try c.decode(SourceReference.self, forKey: .source)
        filename = try c.decode(String.self, forKey: .filename)
        cull = try c.decode(CullDecision.self, forKey: .cull)
        recipe = try c.decodeIfPresent(EditRecipe.self, forKey: .recipe)
        capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt)
        fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize)
        thumbPath = try c.decodeIfPresent(String.self, forKey: .thumbPath)
        gridThumbPath = try c.decodeIfPresent(String.self, forKey: .gridThumbPath)
        proxyPath = try c.decodeIfPresent(String.self, forKey: .proxyPath)
        previewOrigin = try c.decode(PreviewOrigin.self, forKey: .previewOrigin)
        previewLongEdge = try c.decode(Int.self, forKey: .previewLongEdge)
        sharpness = try c.decode(Double.self, forKey: .sharpness)
        exposureHealth = try c.decode(Double.self, forKey: .exposureHealth)
        faceQuality = try c.decode(Double.self, forKey: .faceQuality)
        aesthetic = try c.decode(Double.self, forKey: .aesthetic)
        compositeQuality = try c.decode(Double.self, forKey: .compositeQuality)
        faceDetected = try c.decode(Bool.self, forKey: .faceDetected)
        cullScore = try c.decode(Double.self, forKey: .cullScore)
        cullConfidence = try c.decode(Double.self, forKey: .cullConfidence)
        editConfidence = try c.decode(Double.self, forKey: .editConfidence)
        tasteMatch = try c.decode(Double.self, forKey: .tasteMatch)
        proposedTier = try c.decodeIfPresent(PhotoTier.self, forKey: .proposedTier)
        userDecidedAt = try c.decodeIfPresent(Date.self, forKey: .userDecidedAt)
        settledAt = try c.decodeIfPresent(Date.self, forKey: .settledAt)
        isFlagged = try c.decode(Bool.self, forKey: .isFlagged)
        isBurstHero = try c.decode(Bool.self, forKey: .isBurstHero)
        isClusterHero = try c.decode(Bool.self, forKey: .isClusterHero)
        uncertaintyKind = try c.decode(UncertaintyKind.self, forKey: .uncertaintyKind)
        whyUncertain = try c.decodeIfPresent(String.self, forKey: .whyUncertain)
        whyAction = try c.decodeIfPresent(String.self, forKey: .whyAction)
        burstID = try c.decodeIfPresent(String.self, forKey: .burstID)
        clusterID = try c.decodeIfPresent(String.self, forKey: .clusterID)
        clusterLabel = try c.decodeIfPresent(String.self, forKey: .clusterLabel)
        embedding = try c.decodeIfPresent([Float].self, forKey: .embedding)
        recipeSource = try c.decodeIfPresent(RecipeSource.self, forKey: .recipeSource) ?? .shot
        handRecipe = try c.decodeIfPresent(EditRecipe.self, forKey: .handRecipe)
        imageStats = try c.decodeIfPresent(ImageStats.self, forKey: .imageStats)
    }

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
        embedding: [Float]? = nil,
        recipeSource: RecipeSource = .shot,
        handRecipe: EditRecipe? = nil,
        imageStats: ImageStats? = nil
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
        self.recipeSource = recipeSource
        self.handRecipe = handRecipe
        self.imageStats = imageStats
    }
}

// MARK: - Arrangement / evidence / recommendation boundaries

/// Arrangement only: answers which frames belong to the same moment.
/// It carries no preference, rating, or cull mutation.
nonisolated struct SceneMembership: Codable, Hashable, Sendable {
    var burstID: String?
    var sceneID: String?
}

/// Replaceable technical observations. These may help the photographer
/// inspect a frame but cannot write `CullDecision`.
nonisolated struct QualitySignals: Codable, Hashable, Sendable {
    var sharpness: Double
    var exposureHealth: Double
    var faceDetected: Bool
    var faceQuality: Double
}

/// Future, gated output. Deliberately separate from both `AssetRecord.cull`
/// and persisted ratings so a model can be benchmarked or removed without
/// changing anything the photographer decided.
nonisolated struct RecommendationObservation: Codable, Hashable, Sendable {
    var assetID: UUID
    var sceneID: String
    var modelVersion: String
    var relativeScore: Double
    var generatedAt: Date
}

nonisolated extension AssetRecord {
    var sceneMembership: SceneMembership {
        SceneMembership(burstID: burstID, sceneID: clusterID)
    }

    var qualitySignals: QualitySignals {
        QualitySignals(
            sharpness: sharpness,
            exposureHealth: exposureHealth,
            faceDetected: faceDetected,
            faceQuality: faceQuality
        )
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
    /// Shoot-scoped wholesale exclusions — persist through re-staging and relaunch (hi-fi H6).
    var wholesaleExcludedPhotoIDs: Set<UUID> = []

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, createdAt, rawFolder, jpgFolder, keepRateTarget, jobBrief
        case profile, tasteSourceCount, tasteStrength, assets, finalSetOrder, collections
        case exportHistory, batchHistory, decisionLedger, auditSeedPhotoIDs, workspace
        case wholesaleExcludedPhotoIDs
    }

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
        workspace: WorkspaceRestoreState = .default,
        wholesaleExcludedPhotoIDs: Set<UUID> = []
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
        self.wholesaleExcludedPhotoIDs = wholesaleExcludedPhotoIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(ShootSchemaVersion.self, forKey: .schemaVersion) ?? .current
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        rawFolder = try c.decodeIfPresent(SourceReference.self, forKey: .rawFolder)
        jpgFolder = try c.decodeIfPresent(SourceReference.self, forKey: .jpgFolder)
        keepRateTarget = try c.decodeIfPresent(Double.self, forKey: .keepRateTarget) ?? 0.10
        jobBrief = try c.decodeIfPresent(JobBrief.self, forKey: .jobBrief) ?? JobBrief()
        profile = try c.decodeIfPresent(EditRecipe.self, forKey: .profile) ?? .neutral
        tasteSourceCount = try c.decodeIfPresent(Int.self, forKey: .tasteSourceCount) ?? 0
        tasteStrength = try c.decodeIfPresent(Double.self, forKey: .tasteStrength) ?? 1.0
        assets = try c.decodeIfPresent([AssetRecord].self, forKey: .assets) ?? []
        finalSetOrder = try c.decodeIfPresent(FinalSetOrder.self, forKey: .finalSetOrder) ?? FinalSetOrder()
        collections = try c.decodeIfPresent([ExportCollection].self, forKey: .collections) ?? []
        exportHistory = try c.decodeIfPresent([ExportRecord].self, forKey: .exportHistory) ?? []
        batchHistory = try c.decodeIfPresent([BatchEditCommand].self, forKey: .batchHistory) ?? []
        decisionLedger = try c.decodeIfPresent([DecisionEvent].self, forKey: .decisionLedger) ?? []
        auditSeedPhotoIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .auditSeedPhotoIDs) ?? []
        workspace = try c.decodeIfPresent(WorkspaceRestoreState.self, forKey: .workspace) ?? .default
        wholesaleExcludedPhotoIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .wholesaleExcludedPhotoIDs) ?? []
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
