import Foundation

// MARK: - Tiers & sort

enum PhotoTier: String, Codable, CaseIterable {
    case keep, reject, unranked

    var label: String {
        switch self {
        case .keep: "Keep"
        case .reject: "Reject"
        case .unranked: "—"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "maybe" {
            self = .unranked
        } else if let tier = PhotoTier(rawValue: raw) {
            self = tier
        } else {
            self = .unranked
        }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case uncertain = "Uncertain"
    case similar = "Similar"
    case sharpest = "Sharpest"
    case quality = "Quality"
    case taste = "Taste match"
    case all = "All"

    var id: String { rawValue }
}

enum GridFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case keeps = "Keeps"
    case rejects = "Rejects"
    case flagged = "Needs you"

    var id: String { rawValue }
}

enum UncertaintyKind: String, Codable, Hashable {
    case cullTie
    case cullBorderline
    case editLowConfidence
    case none
}

enum ExportAspect: String, CaseIterable, Identifiable, Codable {
    case fourByFive = "4:5"
    case oneByOne = "1:1"
    case nineBySixteen = "9:16"
    case sixteenByNine = "16:9"

    var id: String { rawValue }

    var ratio: Double {
        switch self {
        case .fourByFive: 4.0 / 5.0
        case .oneByOne: 1.0
        case .nineBySixteen: 9.0 / 16.0
        case .sixteenByNine: 16.0 / 9.0
        }
    }
}

// MARK: - Develop

struct DevelopAdjustments: Codable, Hashable {
    var exposure: Double = 0
    var temperature: Double = 0 // offset from profile Kelvin
    var tint: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
    var texture: Double = 0
    var clarity: Double = 0
    var dehaze: Double = 0
    var vibrance: Double = 0
    var saturation: Double = 0

    static let zero = DevelopAdjustments()

    var isZero: Bool {
        exposure == 0 && temperature == 0 && tint == 0 && contrast == 0
            && highlights == 0 && shadows == 0 && whites == 0 && blacks == 0
            && texture == 0 && clarity == 0 && dehaze == 0 && vibrance == 0 && saturation == 0
    }

    func merged(with other: DevelopAdjustments) -> DevelopAdjustments {
        DevelopAdjustments(
            exposure: exposure + other.exposure,
            temperature: temperature + other.temperature,
            tint: tint + other.tint,
            contrast: contrast + other.contrast,
            highlights: highlights + other.highlights,
            shadows: shadows + other.shadows,
            whites: whites + other.whites,
            blacks: blacks + other.blacks,
            texture: texture + other.texture,
            clarity: clarity + other.clarity,
            dehaze: dehaze + other.dehaze,
            vibrance: vibrance + other.vibrance,
            saturation: saturation + other.saturation
        )
    }

    func scaled(by factor: Double) -> DevelopAdjustments {
        DevelopAdjustments(
            exposure: exposure * factor,
            temperature: temperature * factor,
            tint: tint * factor,
            contrast: contrast * factor,
            highlights: highlights * factor,
            shadows: shadows * factor,
            whites: whites * factor,
            blacks: blacks * factor,
            texture: texture * factor,
            clarity: clarity * factor,
            dehaze: dehaze * factor,
            vibrance: vibrance * factor,
            saturation: saturation * factor
        )
    }

    static func lerp(_ a: DevelopAdjustments, _ b: DevelopAdjustments, t: Double) -> DevelopAdjustments {
        let u = 1 - t
        return DevelopAdjustments(
            exposure: a.exposure * u + b.exposure * t,
            temperature: a.temperature * u + b.temperature * t,
            tint: a.tint * u + b.tint * t,
            contrast: a.contrast * u + b.contrast * t,
            highlights: a.highlights * u + b.highlights * t,
            shadows: a.shadows * u + b.shadows * t,
            whites: a.whites * u + b.whites * t,
            blacks: a.blacks * u + b.blacks * t,
            texture: a.texture * u + b.texture * t,
            clarity: a.clarity * u + b.clarity * t,
            dehaze: a.dehaze * u + b.dehaze * t,
            vibrance: a.vibrance * u + b.vibrance * t,
            saturation: a.saturation * u + b.saturation * t
        )
    }
}

/// Absolute Lightroom-style develop recipe (crs:* compatible).
struct DevelopRecipe: Codable, Hashable {
    var exposure: Double = 0
    var temperature: Double = 6500
    var tint: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
    var texture: Double = 0
    var clarity: Double = 0
    var dehaze: Double = 0
    var vibrance: Double = 0
    var saturation: Double = 0
    var sharpness: Double = 0
    var luminanceNR: Double = 0
    var sourceNeighbors: [String] = []
    var confidence: Double = 1

    static let neutral = DevelopRecipe()

    var hasSettings: Bool {
        exposure != 0 || temperature != 6500 || tint != 0 || contrast != 0
            || highlights != 0 || shadows != 0 || whites != 0 || blacks != 0
            || texture != 0 || clarity != 0 || dehaze != 0 || vibrance != 0 || saturation != 0
    }

    /// Offsets relative to a project baseline profile (for UI sliders).
    func offsets(from profile: DevelopRecipe) -> DevelopAdjustments {
        DevelopAdjustments(
            exposure: exposure - profile.exposure,
            temperature: temperature - profile.temperature,
            tint: tint - profile.tint,
            contrast: contrast - profile.contrast,
            highlights: highlights - profile.highlights,
            shadows: shadows - profile.shadows,
            whites: whites - profile.whites,
            blacks: blacks - profile.blacks,
            texture: texture - profile.texture,
            clarity: clarity - profile.clarity,
            dehaze: dehaze - profile.dehaze,
            vibrance: vibrance - profile.vibrance,
            saturation: saturation - profile.saturation
        )
    }

    func applying(_ offsets: DevelopAdjustments) -> DevelopRecipe {
        var r = self
        r.exposure += offsets.exposure
        r.temperature += offsets.temperature
        r.tint += offsets.tint
        r.contrast += offsets.contrast
        r.highlights += offsets.highlights
        r.shadows += offsets.shadows
        r.whites += offsets.whites
        r.blacks += offsets.blacks
        r.texture += offsets.texture
        r.clarity += offsets.clarity
        r.dehaze += offsets.dehaze
        r.vibrance += offsets.vibrance
        r.saturation += offsets.saturation
        return r
    }

    static func lerp(_ a: DevelopRecipe, _ b: DevelopRecipe, t: Double) -> DevelopRecipe {
        let u = 1 - t
        return DevelopRecipe(
            exposure: a.exposure * u + b.exposure * t,
            temperature: a.temperature * u + b.temperature * t,
            tint: a.tint * u + b.tint * t,
            contrast: a.contrast * u + b.contrast * t,
            highlights: a.highlights * u + b.highlights * t,
            shadows: a.shadows * u + b.shadows * t,
            whites: a.whites * u + b.whites * t,
            blacks: a.blacks * u + b.blacks * t,
            texture: a.texture * u + b.texture * t,
            clarity: a.clarity * u + b.clarity * t,
            dehaze: a.dehaze * u + b.dehaze * t,
            vibrance: a.vibrance * u + b.vibrance * t,
            saturation: a.saturation * u + b.saturation * t,
            sharpness: a.sharpness * u + b.sharpness * t,
            luminanceNR: a.luminanceNR * u + b.luminanceNR * t,
            sourceNeighbors: t < 0.5 ? a.sourceNeighbors : b.sourceNeighbors,
            confidence: a.confidence * u + b.confidence * t
        )
    }
}

/// Back-compat alias used by older UI code.
typealias DevelopProfile = DevelopRecipe

extension DevelopRecipe {
    var sourceCount: Int { sourceNeighbors.isEmpty ? (hasSettings ? 1 : 0) : sourceNeighbors.count }
    var hasDevelopSettings: Bool { hasSettings }

    var asAdjustments: DevelopAdjustments {
        DevelopAdjustments(
            exposure: exposure,
            temperature: 0,
            tint: tint,
            contrast: contrast,
            highlights: highlights,
            shadows: shadows,
            whites: whites,
            blacks: blacks,
            texture: texture,
            clarity: clarity,
            dehaze: dehaze,
            vibrance: vibrance,
            saturation: saturation
        )
    }
}

// MARK: - Photo

struct PhotoRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var rawPath: String
    var filename: String
    var thumbPath: String?
    var gridThumbPath: String?
    var proxyPath: String?
    var capturedAt: Date?
    var burstID: String?
    var clusterID: String?
    var clusterLabel: String?

    // Quality axes
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

    var tier: PhotoTier
    var isFlagged: Bool
    var isBurstHero: Bool
    var isClusterHero: Bool
    var uncertaintyKind: UncertaintyKind
    var whyUncertain: String?
    /// Agent explanation for auto or user-confirmed action.
    var whyAction: String?

    var recipe: DevelopRecipe?
    var embedding: [Float]?

    init(
        id: UUID = UUID(),
        rawPath: String,
        filename: String,
        thumbPath: String? = nil,
        gridThumbPath: String? = nil,
        proxyPath: String? = nil,
        capturedAt: Date? = nil,
        burstID: String? = nil,
        clusterID: String? = nil,
        clusterLabel: String? = nil,
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
        tier: PhotoTier = .unranked,
        isFlagged: Bool = false,
        isBurstHero: Bool = true,
        isClusterHero: Bool = true,
        uncertaintyKind: UncertaintyKind = .none,
        whyUncertain: String? = nil,
        whyAction: String? = nil,
        recipe: DevelopRecipe? = nil,
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.rawPath = rawPath
        self.filename = filename
        self.thumbPath = thumbPath
        self.gridThumbPath = gridThumbPath
        self.proxyPath = proxyPath
        self.capturedAt = capturedAt
        self.burstID = burstID
        self.clusterID = clusterID
        self.clusterLabel = clusterLabel
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
        self.tier = tier
        self.isFlagged = isFlagged
        self.isBurstHero = isBurstHero
        self.isClusterHero = isClusterHero
        self.uncertaintyKind = uncertaintyKind
        self.whyUncertain = whyUncertain
        self.whyAction = whyAction
        self.recipe = recipe
        self.embedding = embedding
    }

    var displayThumbPath: String? { gridThumbPath ?? thumbPath }

    /// Larger tier for carousels and filmstrip (1600px class).
    var previewPath: String? { thumbPath ?? gridThumbPath }

    /// Best available path for sharp display at ~2048px.
    var sharpPath: String? { proxyPath ?? thumbPath ?? gridThumbPath }

    var isUncertain: Bool {
        isFlagged || uncertaintyKind != .none
    }

    var whySummary: String {
        if let whyAction, !whyAction.isEmpty { return whyAction }
        if let whyUncertain, !whyUncertain.isEmpty { return whyUncertain }
        var parts: [String] = []
        parts.append("Sharp \(String(format: "%.2f", sharpness))")
        parts.append("Quality \(String(format: "%.2f", compositeQuality))")
        parts.append(faceDetected ? "Face \(String(format: "%.2f", faceQuality))" : "No face")
        if let clusterLabel { parts.append(clusterLabel) }
        if isBurstHero { parts.append("Burst hero") }
        return parts.joined(separator: " · ")
    }

    var effectiveRecipe: DevelopRecipe {
        recipe ?? .neutral
    }
}

struct PhotoCluster: Identifiable, Hashable {
    let id: String
    var label: String
    /// Human reason this set was grouped (shown in group intro).
    var whyGrouped: String
    var photoIDs: [UUID]
    var heroID: UUID?
    var faceCount: Int
    var timeSpanSeconds: TimeInterval?
}

struct ExportCollection: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var aspect: ExportAspect
    var photoIDs: [UUID]
}

struct LuminaProject: Codable {
    var name: String
    var rawFolder: String?
    var jpgFolder: String?
    var keepRateTarget: Double = 0.10
    var jobBrief: JobBrief = JobBrief()
    var profile: DevelopRecipe = .neutral
    /// JPGs scanned for XMP taste extraction at import.
    var tasteSourceCount: Int = 0
    /// 0…1.5 — scales extracted profile offsets (1.0 = 100%).
    var tasteStrength: Double = 1.0
    var photos: [PhotoRecord] = []
    var collections: [ExportCollection] = []
    var createdAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case name, rawFolder, jpgFolder, keepRateTarget, jobBrief, profile
        case tasteSourceCount, tasteStrength, photos, collections, createdAt
        case globalAdjustments
    }

    init(
        name: String,
        rawFolder: String? = nil,
        jpgFolder: String? = nil,
        keepRateTarget: Double = 0.10,
        jobBrief: JobBrief = JobBrief(),
        profile: DevelopRecipe = .neutral,
        tasteSourceCount: Int = 0,
        tasteStrength: Double = 1.0,
        photos: [PhotoRecord] = [],
        collections: [ExportCollection] = [],
        createdAt: Date = Date()
    ) {
        self.name = name
        self.rawFolder = rawFolder
        self.jpgFolder = jpgFolder
        self.keepRateTarget = keepRateTarget
        self.jobBrief = jobBrief
        self.profile = profile
        self.tasteSourceCount = tasteSourceCount
        self.tasteStrength = tasteStrength
        self.photos = photos
        self.collections = collections
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        rawFolder = try c.decodeIfPresent(String.self, forKey: .rawFolder)
        jpgFolder = try c.decodeIfPresent(String.self, forKey: .jpgFolder)
        keepRateTarget = try c.decodeIfPresent(Double.self, forKey: .keepRateTarget) ?? 0.10
        jobBrief = try c.decodeIfPresent(JobBrief.self, forKey: .jobBrief) ?? JobBrief()
        profile = try c.decodeIfPresent(DevelopRecipe.self, forKey: .profile) ?? .neutral
        tasteSourceCount = try c.decodeIfPresent(Int.self, forKey: .tasteSourceCount) ?? profile.sourceCount
        tasteStrength = try c.decodeIfPresent(Double.self, forKey: .tasteStrength) ?? 1.0
        photos = try c.decodeIfPresent([PhotoRecord].self, forKey: .photos) ?? []
        collections = try c.decodeIfPresent([ExportCollection].self, forKey: .collections) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(rawFolder, forKey: .rawFolder)
        try c.encodeIfPresent(jpgFolder, forKey: .jpgFolder)
        try c.encode(keepRateTarget, forKey: .keepRateTarget)
        try c.encode(jobBrief, forKey: .jobBrief)
        try c.encode(profile, forKey: .profile)
        try c.encode(tasteSourceCount, forKey: .tasteSourceCount)
        try c.encode(tasteStrength, forKey: .tasteStrength)
        try c.encode(photos, forKey: .photos)
        try c.encode(collections, forKey: .collections)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Import events

enum ImportPhase: String, Sendable, CaseIterable {
    case metadata
    case taste
    case previews
    case quality
    case grouping
    case faces
    case edits
    case ready

    var title: String {
        switch self {
        case .metadata: "Reading your roll"
        case .taste: "Learning your look"
        case .previews: "Waking up previews"
        case .quality: "Scoring sharpness & light"
        case .grouping: "Finding similar sets"
        case .faces: "Checking faces"
        case .edits: "Applying your taste"
        case .ready: "Ready"
        }
    }
}

struct ImportProgress: Sendable, Equatable {
    var phase: ImportPhase
    var detail: String
    var completed: Int
    var total: Int
    /// 0…1 across the whole import pipeline.
    var overallFraction: Double
    var recentThumbPaths: [String]

    static let zero = ImportProgress(
        phase: .metadata,
        detail: "Starting…",
        completed: 0,
        total: 0,
        overallFraction: 0,
        recentThumbPaths: []
    )
}

enum ImportEvent: Sendable {
    case progress(ImportProgress)
    case status(String)
    case photosReady([PhotoRecord], profile: DevelopRecipe)
    case photosUpdated([PhotoRecord])
    case finished(LuminaProject)
    case failed(String)
}
