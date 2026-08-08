import Foundation

typealias PhotoID = UUID

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
    case similar = "Similar"
    case sharpest = "Sharpest"
    case quality = "Quality"
    case taste = "Taste match"
    case all = "All"

    var id: String { rawValue }

    /// Grid overview lens only — uncertain queue lives in Decide leftovers.
    static var gridLensModes: [SortMode] { allCases }
}

enum GridFilter: String, CaseIterable, Identifiable, Codable, Sendable {
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

enum SessionLens: Equatable {
    case grid
    case audit(AuditReason)
}

enum AuditReason: String, Codable, CaseIterable, Hashable, Identifiable {
    case cullTie
    case cullBorderline
    case editLowConfidence
    case hardReject

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cullTie: "Near duplicates"
        case .cullBorderline: "Borderline calls"
        case .editLowConfidence: "Low-confidence edits"
        case .hardReject: "Sharpness rejects"
        }
    }
}

struct AuditPile: Identifiable, Equatable {
    var reason: AuditReason
    var photos: [PhotoRecord]

    var id: AuditReason { reason }
}

enum DecisionEventKind: String, Codable {
    case rescued
    case pileAccepted
    /// One workbench round — every per-photo change in a single ledger transaction.
    case round
}

struct DecisionEvent: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: DecisionEventKind
    var reason: AuditReason
    var photoIDs: [PhotoID]
    var proposedTiers: [PhotoID: PhotoTier]
    var confidenceByPhoto: [PhotoID: Double]
    var timestamp: Date = Date()
}

struct AuditReasonMetrics: Equatable {
    var proposed: Int
    var rescued: Int
    var seeded: Int
    var seedsCaught: Int

    var rescueRate: Double {
        guard proposed > 0 else { return 0 }
        return Double(rescued) / Double(proposed)
    }

    var seedCatchRate: Double {
        guard seeded > 0 else { return 1 }
        return Double(seedsCaught) / Double(seeded)
    }
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
    var sharpness: Double = 0
    var luminanceNR: Double = 0

    static let zero = DevelopAdjustments()

    init(
        exposure: Double = 0, temperature: Double = 0, tint: Double = 0,
        contrast: Double = 0, highlights: Double = 0, shadows: Double = 0,
        whites: Double = 0, blacks: Double = 0, texture: Double = 0,
        clarity: Double = 0, dehaze: Double = 0, vibrance: Double = 0,
        saturation: Double = 0, sharpness: Double = 0, luminanceNR: Double = 0
    ) {
        self.exposure = exposure
        self.temperature = temperature
        self.tint = tint
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
        self.texture = texture
        self.clarity = clarity
        self.dehaze = dehaze
        self.vibrance = vibrance
        self.saturation = saturation
        self.sharpness = sharpness
        self.luminanceNR = luminanceNR
    }

    // Tolerant decoding — older saved state lacks the newer detail fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        whites = try c.decodeIfPresent(Double.self, forKey: .whites) ?? 0
        blacks = try c.decodeIfPresent(Double.self, forKey: .blacks) ?? 0
        texture = try c.decodeIfPresent(Double.self, forKey: .texture) ?? 0
        clarity = try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        dehaze = try c.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0
        vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        luminanceNR = try c.decodeIfPresent(Double.self, forKey: .luminanceNR) ?? 0
    }

    var isZero: Bool {
        exposure == 0 && temperature == 0 && tint == 0 && contrast == 0
            && highlights == 0 && shadows == 0 && whites == 0 && blacks == 0
            && texture == 0 && clarity == 0 && dehaze == 0 && vibrance == 0 && saturation == 0
            && sharpness == 0 && luminanceNR == 0
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
            saturation: saturation + other.saturation,
            sharpness: sharpness + other.sharpness,
            luminanceNR: luminanceNR + other.luminanceNR
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
            saturation: saturation * factor,
            sharpness: sharpness * factor,
            luminanceNR: luminanceNR * factor
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
            saturation: a.saturation * u + b.saturation * t,
            sharpness: a.sharpness * u + b.sharpness * t,
            luminanceNR: a.luminanceNR * u + b.luminanceNR * t
        )
    }
}

/// One clone-based heal spot, in normalized oriented image coordinates
/// (origin top-left). `sourceDX/DY` point at the donor region relative to the
/// spot center. This is classic clone healing — not generative fill — and it
/// renders identically in preview and export.
struct RetouchSpot: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    /// Spot center 0…1.
    var x: Double
    var y: Double
    /// Radius normalized to image width.
    var radius: Double
    /// Donor offset, normalized to image width/height.
    var sourceDX: Double
    var sourceDY: Double

    var fingerprint: String {
        String(format: "%.4f,%.4f,%.4f,%.4f,%.4f", x, y, radius, sourceDX, sourceDY)
    }
}

/// Absolute Lightroom-style develop recipe (crs:* compatible).
///
/// **Superseded for P0 photo persistence** by `EditRecipe`, which also carries
/// crop / straighten. `DevelopRecipe` remains as the taste / XMP / older-UI adapter.
struct DevelopRecipe: Codable, Hashable {
    var exposure: Double = 0
    var temperature: Double = EditRecipe.neutralTemperature
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
    /// Clone-heal spots (erase tool). Applied in preview and export.
    var retouch: [RetouchSpot] = []
    var sourceNeighbors: [String] = []
    var confidence: Double = 1

    static let neutral = DevelopRecipe()

    init(
        exposure: Double = 0, temperature: Double = EditRecipe.neutralTemperature, tint: Double = 0,
        contrast: Double = 0, highlights: Double = 0, shadows: Double = 0,
        whites: Double = 0, blacks: Double = 0, texture: Double = 0,
        clarity: Double = 0, dehaze: Double = 0, vibrance: Double = 0,
        saturation: Double = 0, sharpness: Double = 0, luminanceNR: Double = 0,
        retouch: [RetouchSpot] = [], sourceNeighbors: [String] = [], confidence: Double = 1
    ) {
        self.exposure = exposure
        self.temperature = temperature
        self.tint = tint
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
        self.texture = texture
        self.clarity = clarity
        self.dehaze = dehaze
        self.vibrance = vibrance
        self.saturation = saturation
        self.sharpness = sharpness
        self.luminanceNR = luminanceNR
        self.retouch = retouch
        self.sourceNeighbors = sourceNeighbors
        self.confidence = confidence
    }

    // Tolerant decoding — projects saved before retouch/detail fields existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? EditRecipe.neutralTemperature
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        whites = try c.decodeIfPresent(Double.self, forKey: .whites) ?? 0
        blacks = try c.decodeIfPresent(Double.self, forKey: .blacks) ?? 0
        texture = try c.decodeIfPresent(Double.self, forKey: .texture) ?? 0
        clarity = try c.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        dehaze = try c.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0
        vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        luminanceNR = try c.decodeIfPresent(Double.self, forKey: .luminanceNR) ?? 0
        retouch = try c.decodeIfPresent([RetouchSpot].self, forKey: .retouch) ?? []
        sourceNeighbors = try c.decodeIfPresent([String].self, forKey: .sourceNeighbors) ?? []
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 1
    }

    var hasSettings: Bool {
        exposure != 0 || temperature != EditRecipe.neutralTemperature || tint != 0 || contrast != 0
            || highlights != 0 || shadows != 0 || whites != 0 || blacks != 0
            || texture != 0 || clarity != 0 || dehaze != 0 || vibrance != 0 || saturation != 0
            || sharpness != 0 || luminanceNR != 0 || !retouch.isEmpty
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
        r.sharpness = max(0, r.sharpness + offsets.sharpness)
        r.luminanceNR = max(0, r.luminanceNR + offsets.luminanceNR)
        return r
    }

    /// Calibrates an auto/taste recipe (Lightroom crs values) onto Lumina's
    /// honestly-implemented control set. Whites/Blacks/Clarity/Dehaze/Texture
    /// have no defensible algorithm here, so their tonal intent is folded into
    /// the trusted controls with conservative, documented factors — this keeps
    /// LR-derived auto edits visually closer to the Lightroom rendering intent
    /// instead of silently dropping half the recipe.
    func lrCalibrated() -> DevelopRecipe {
        var r = self
        r.highlights = clampCRS(r.highlights + r.whites * 0.5)
        r.shadows = clampCRS(r.shadows + r.blacks * 0.5)
        r.contrast = clampCRS(r.contrast + r.clarity * 0.3 + r.dehaze * 0.2)
        r.whites = 0
        r.blacks = 0
        r.clarity = 0
        r.dehaze = 0
        r.texture = 0
        if r.temperature <= 0 { r.temperature = EditRecipe.neutralTemperature }
        r.temperature = min(max(r.temperature, 2500), 10000)
        r.exposure = min(max(r.exposure, -3), 3)
        r.sharpness = min(max(r.sharpness, 0), 150)
        r.luminanceNR = min(max(r.luminanceNR, 0), 100)
        return r
    }

    private func clampCRS(_ v: Double) -> Double {
        min(max(v, -100), 100)
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
            retouch: t < 0.5 ? a.retouch : b.retouch,
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

enum PreviewOrigin: String, Codable, Hashable {
    case embedded
    case synthesized
    case processed
    case unknown
}

struct PhotoRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var rawPath: String
    var filename: String
    var thumbPath: String?
    var gridThumbPath: String?
    var proxyPath: String?
    /// How the browse preview was produced — never demosaic on the interactive path.
    var previewOrigin: PreviewOrigin
    var previewLongEdge: Int
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
    /// Agent recommendation. It is materialized into `tier` only when the user accepts its pile.
    var proposedTier: PhotoTier?
    var userDecidedAt: Date?
    /// Materialized frontier membership; once set, background refinement may never reshape this record.
    var settledAt: Date?
    var isFlagged: Bool
    var isBurstHero: Bool
    var isClusterHero: Bool
    var uncertaintyKind: UncertaintyKind
    var whyUncertain: String?
    /// Agent explanation for auto or user-confirmed action.
    var whyAction: String?

    /// Canonical P0 edit recipe (tone + geometry + retouch). Prefer this over `recipe`.
    var editRecipe: EditRecipe?
    var embedding: [Float]?

    // MARK: Stable identity / source (P0)

    /// Opaque rediscovery key — volume + relative path + size + capture.
    var sourceKey: String?
    var sourceRelativePath: String?
    var sourceVolumeID: String?
    var sourceBookmark: Data?
    var sourceAvailability: SourceAvailability
    var fileSize: Int64?

    /// Legacy DevelopRecipe bridge — tone/retouch only. Geometry lives on `editRecipe`.
    var recipe: DevelopRecipe? {
        get { editRecipe?.asDevelopRecipe }
        set {
            if let newValue {
                if let existing = editRecipe {
                    editRecipe = existing.replacingTone(from: newValue)
                } else {
                    editRecipe = EditRecipe(from: newValue)
                }
            } else {
                editRecipe = nil
            }
        }
    }

    init(
        id: UUID = UUID(),
        rawPath: String,
        filename: String,
        thumbPath: String? = nil,
        gridThumbPath: String? = nil,
        proxyPath: String? = nil,
        previewOrigin: PreviewOrigin = .unknown,
        previewLongEdge: Int = 0,
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
        proposedTier: PhotoTier? = nil,
        userDecidedAt: Date? = nil,
        settledAt: Date? = nil,
        isFlagged: Bool = false,
        isBurstHero: Bool = true,
        isClusterHero: Bool = true,
        uncertaintyKind: UncertaintyKind = .none,
        whyUncertain: String? = nil,
        whyAction: String? = nil,
        recipe: DevelopRecipe? = nil,
        editRecipe: EditRecipe? = nil,
        embedding: [Float]? = nil,
        sourceKey: String? = nil,
        sourceRelativePath: String? = nil,
        sourceVolumeID: String? = nil,
        sourceBookmark: Data? = nil,
        sourceAvailability: SourceAvailability = .unknown,
        fileSize: Int64? = nil
    ) {
        self.id = id
        self.rawPath = rawPath
        self.filename = filename
        self.thumbPath = thumbPath
        self.gridThumbPath = gridThumbPath
        self.proxyPath = proxyPath
        self.previewOrigin = previewOrigin
        self.previewLongEdge = previewLongEdge
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
        self.proposedTier = proposedTier
        self.userDecidedAt = userDecidedAt
        self.settledAt = settledAt
        self.isFlagged = isFlagged
        self.isBurstHero = isBurstHero
        self.isClusterHero = isClusterHero
        self.uncertaintyKind = uncertaintyKind
        self.whyUncertain = whyUncertain
        self.whyAction = whyAction
        if let editRecipe {
            self.editRecipe = editRecipe
        } else if let recipe {
            self.editRecipe = EditRecipe(from: recipe)
        } else {
            self.editRecipe = nil
        }
        self.embedding = embedding
        self.sourceKey = sourceKey
        self.sourceRelativePath = sourceRelativePath
        self.sourceVolumeID = sourceVolumeID
        self.sourceBookmark = sourceBookmark
        self.sourceAvailability = sourceAvailability
        self.fileSize = fileSize
    }

    var displayThumbPath: String? { gridThumbPath ?? thumbPath ?? rawPath }

    /// Larger tier for carousels and filmstrip (1600px class).
    var previewPath: String? { thumbPath ?? gridThumbPath ?? rawPath }

    /// Best available path for sharp display at ~2048px.
    var sharpPath: String? { proxyPath ?? thumbPath ?? gridThumbPath ?? rawPath }

    var isUncertain: Bool {
        isFlagged || uncertaintyKind != .none
    }

    var auditReason: AuditReason? {
        if sharpness < 0.12, proposedTier == .reject {
            return .hardReject
        }
        switch uncertaintyKind {
        case .cullTie: return .cullTie
        case .cullBorderline: return .cullBorderline
        case .editLowConfidence: return .editLowConfidence
        case .none: return nil
        }
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

    var effectiveEditRecipe: EditRecipe {
        editRecipe ?? .neutral
    }

    enum CodingKeys: String, CodingKey {
        case id, rawPath, filename, thumbPath, gridThumbPath, proxyPath
        case previewOrigin, previewLongEdge
        case capturedAt, burstID, clusterID, clusterLabel
        case sharpness, exposureHealth, faceQuality, aesthetic, compositeQuality, faceDetected
        case cullScore, cullConfidence, editConfidence, tasteMatch
        case tier, proposedTier, userDecidedAt, settledAt, isFlagged, isBurstHero, isClusterHero
        case uncertaintyKind, whyUncertain, whyAction, recipe, editRecipe, embedding
        case sourceKey, sourceRelativePath, sourceVolumeID, sourceBookmark, sourceAvailability, fileSize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        rawPath = try c.decode(String.self, forKey: .rawPath)
        filename = try c.decode(String.self, forKey: .filename)
        thumbPath = try c.decodeIfPresent(String.self, forKey: .thumbPath)
        gridThumbPath = try c.decodeIfPresent(String.self, forKey: .gridThumbPath)
        proxyPath = try c.decodeIfPresent(String.self, forKey: .proxyPath)
        previewOrigin = try c.decodeIfPresent(PreviewOrigin.self, forKey: .previewOrigin) ?? .unknown
        previewLongEdge = try c.decodeIfPresent(Int.self, forKey: .previewLongEdge) ?? 0
        capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt)
        burstID = try c.decodeIfPresent(String.self, forKey: .burstID)
        clusterID = try c.decodeIfPresent(String.self, forKey: .clusterID)
        clusterLabel = try c.decodeIfPresent(String.self, forKey: .clusterLabel)
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        exposureHealth = try c.decodeIfPresent(Double.self, forKey: .exposureHealth) ?? 0.5
        faceQuality = try c.decodeIfPresent(Double.self, forKey: .faceQuality) ?? 0
        aesthetic = try c.decodeIfPresent(Double.self, forKey: .aesthetic) ?? 0.5
        compositeQuality = try c.decodeIfPresent(Double.self, forKey: .compositeQuality) ?? 0
        faceDetected = try c.decodeIfPresent(Bool.self, forKey: .faceDetected) ?? false
        cullScore = try c.decodeIfPresent(Double.self, forKey: .cullScore) ?? 0
        cullConfidence = try c.decodeIfPresent(Double.self, forKey: .cullConfidence) ?? 0
        editConfidence = try c.decodeIfPresent(Double.self, forKey: .editConfidence) ?? 1
        tasteMatch = try c.decodeIfPresent(Double.self, forKey: .tasteMatch) ?? 0.5
        tier = try c.decodeIfPresent(PhotoTier.self, forKey: .tier) ?? .unranked
        proposedTier = try c.decodeIfPresent(PhotoTier.self, forKey: .proposedTier)
        userDecidedAt = try c.decodeIfPresent(Date.self, forKey: .userDecidedAt)
        settledAt = try c.decodeIfPresent(Date.self, forKey: .settledAt)
        isFlagged = try c.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
        isBurstHero = try c.decodeIfPresent(Bool.self, forKey: .isBurstHero) ?? true
        isClusterHero = try c.decodeIfPresent(Bool.self, forKey: .isClusterHero) ?? true
        uncertaintyKind = try c.decodeIfPresent(UncertaintyKind.self, forKey: .uncertaintyKind) ?? .none
        whyUncertain = try c.decodeIfPresent(String.self, forKey: .whyUncertain)
        whyAction = try c.decodeIfPresent(String.self, forKey: .whyAction)
        embedding = try c.decodeIfPresent([Float].self, forKey: .embedding)
        sourceKey = try c.decodeIfPresent(String.self, forKey: .sourceKey)
        sourceRelativePath = try c.decodeIfPresent(String.self, forKey: .sourceRelativePath)
        sourceVolumeID = try c.decodeIfPresent(String.self, forKey: .sourceVolumeID)
        sourceBookmark = try c.decodeIfPresent(Data.self, forKey: .sourceBookmark)
        sourceAvailability = try c.decodeIfPresent(SourceAvailability.self, forKey: .sourceAvailability) ?? .unknown
        fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize)

        // Prefer explicit editRecipe; else migrate legacy DevelopRecipe under `recipe`.
        if let modern = try c.decodeIfPresent(EditRecipe.self, forKey: .editRecipe) {
            editRecipe = EditRecipe.migrate(modern)
        } else if let legacy = try c.decodeIfPresent(DevelopRecipe.self, forKey: .recipe) {
            editRecipe = EditRecipe(from: legacy)
        } else if let modernUnderRecipe = try? c.decodeIfPresent(EditRecipe.self, forKey: .recipe) {
            editRecipe = EditRecipe.migrate(modernUnderRecipe)
        } else {
            editRecipe = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(rawPath, forKey: .rawPath)
        try c.encode(filename, forKey: .filename)
        try c.encodeIfPresent(thumbPath, forKey: .thumbPath)
        try c.encodeIfPresent(gridThumbPath, forKey: .gridThumbPath)
        try c.encodeIfPresent(proxyPath, forKey: .proxyPath)
        try c.encode(previewOrigin, forKey: .previewOrigin)
        try c.encode(previewLongEdge, forKey: .previewLongEdge)
        try c.encodeIfPresent(capturedAt, forKey: .capturedAt)
        try c.encodeIfPresent(burstID, forKey: .burstID)
        try c.encodeIfPresent(clusterID, forKey: .clusterID)
        try c.encodeIfPresent(clusterLabel, forKey: .clusterLabel)
        try c.encode(sharpness, forKey: .sharpness)
        try c.encode(exposureHealth, forKey: .exposureHealth)
        try c.encode(faceQuality, forKey: .faceQuality)
        try c.encode(aesthetic, forKey: .aesthetic)
        try c.encode(compositeQuality, forKey: .compositeQuality)
        try c.encode(faceDetected, forKey: .faceDetected)
        try c.encode(cullScore, forKey: .cullScore)
        try c.encode(cullConfidence, forKey: .cullConfidence)
        try c.encode(editConfidence, forKey: .editConfidence)
        try c.encode(tasteMatch, forKey: .tasteMatch)
        try c.encode(tier, forKey: .tier)
        try c.encodeIfPresent(proposedTier, forKey: .proposedTier)
        try c.encodeIfPresent(userDecidedAt, forKey: .userDecidedAt)
        try c.encodeIfPresent(settledAt, forKey: .settledAt)
        try c.encode(isFlagged, forKey: .isFlagged)
        try c.encode(isBurstHero, forKey: .isBurstHero)
        try c.encode(isClusterHero, forKey: .isClusterHero)
        try c.encode(uncertaintyKind, forKey: .uncertaintyKind)
        try c.encodeIfPresent(whyUncertain, forKey: .whyUncertain)
        try c.encodeIfPresent(whyAction, forKey: .whyAction)
        // Canonical key — do not also write legacy `recipe` (avoids dual representations).
        try c.encodeIfPresent(editRecipe, forKey: .editRecipe)
        try c.encodeIfPresent(embedding, forKey: .embedding)
        try c.encodeIfPresent(sourceKey, forKey: .sourceKey)
        try c.encodeIfPresent(sourceRelativePath, forKey: .sourceRelativePath)
        try c.encodeIfPresent(sourceVolumeID, forKey: .sourceVolumeID)
        try c.encodeIfPresent(sourceBookmark, forKey: .sourceBookmark)
        try c.encode(sourceAvailability, forKey: .sourceAvailability)
        try c.encodeIfPresent(fileSize, forKey: .fileSize)
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
    /// Legacy taste baseline (DevelopRecipe). Prefer `editProfile` for P0.
    var profile: DevelopRecipe = .neutral
    /// JPGs scanned for XMP taste extraction at import.
    var tasteSourceCount: Int = 0
    /// 0…1.5 — scales extracted profile offsets (1.0 = 100%).
    var tasteStrength: Double = 1.0
    var photos: [PhotoRecord] = []
    var collections: [ExportCollection] = []
    /// Durable identity cursor. Lens is deliberately view-only and is never encoded.
    var cursorPhotoID: PhotoID?
    /// Materialized user acceptance/rescue history; append-only.
    var decisionLedger: [DecisionEvent] = []
    /// Known-good QA fixtures intentionally placed in proposal piles.
    var auditSeedPhotoIDs: Set<PhotoID> = []
    var createdAt: Date = Date()

    // MARK: P0 runtime fields (persisted via ShootRecord, not dual recipe blobs)

    var shootID: UUID?
    var editProfile: EditRecipe = .neutral
    var finalSetOrder: FinalSetOrder?
    var exportHistory: [ExportRecord]?
    var batchHistory: [BatchEditCommand]?
    var workspaceRestore: WorkspaceRestoreState?

    enum CodingKeys: String, CodingKey {
        case name, rawFolder, jpgFolder, keepRateTarget, jobBrief, profile
        case tasteSourceCount, tasteStrength, photos, collections, cursorPhotoID, decisionLedger
        case auditSeedPhotoIDs, createdAt
        case globalAdjustments
        case shootID, editProfile, finalSetOrder, exportHistory, batchHistory, workspaceRestore
        case schemaVersion
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
        cursorPhotoID: PhotoID? = nil,
        decisionLedger: [DecisionEvent] = [],
        auditSeedPhotoIDs: Set<PhotoID> = [],
        createdAt: Date = Date()
    ) {
        self.name = name
        self.rawFolder = rawFolder
        self.jpgFolder = jpgFolder
        self.keepRateTarget = keepRateTarget
        self.jobBrief = jobBrief
        self.profile = profile
        self.editProfile = EditRecipe(from: profile)
        self.tasteSourceCount = tasteSourceCount
        self.tasteStrength = tasteStrength
        self.photos = photos
        self.collections = collections
        self.cursorPhotoID = cursorPhotoID
        self.decisionLedger = decisionLedger
        self.auditSeedPhotoIDs = auditSeedPhotoIDs
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
        if let edit = try c.decodeIfPresent(EditRecipe.self, forKey: .editProfile) {
            editProfile = EditRecipe.migrate(edit)
            profile = editProfile.asDevelopRecipe
        } else {
            editProfile = EditRecipe(from: profile)
        }
        tasteSourceCount = try c.decodeIfPresent(Int.self, forKey: .tasteSourceCount) ?? profile.sourceCount
        tasteStrength = try c.decodeIfPresent(Double.self, forKey: .tasteStrength) ?? 1.0
        photos = try c.decodeIfPresent([PhotoRecord].self, forKey: .photos) ?? []
        collections = try c.decodeIfPresent([ExportCollection].self, forKey: .collections) ?? []
        cursorPhotoID = try c.decodeIfPresent(PhotoID.self, forKey: .cursorPhotoID)
        decisionLedger = try c.decodeIfPresent([DecisionEvent].self, forKey: .decisionLedger) ?? []
        auditSeedPhotoIDs = try c.decodeIfPresent(Set<PhotoID>.self, forKey: .auditSeedPhotoIDs) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        shootID = try c.decodeIfPresent(UUID.self, forKey: .shootID)
        finalSetOrder = try c.decodeIfPresent(FinalSetOrder.self, forKey: .finalSetOrder)
        exportHistory = try c.decodeIfPresent([ExportRecord].self, forKey: .exportHistory)
        batchHistory = try c.decodeIfPresent([BatchEditCommand].self, forKey: .batchHistory)
        workspaceRestore = try c.decodeIfPresent(WorkspaceRestoreState.self, forKey: .workspaceRestore)
    }

    func encode(to encoder: Encoder) throws {
        // Legacy encode path retained for tests; production persistence uses ShootRecord.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(rawFolder, forKey: .rawFolder)
        try c.encodeIfPresent(jpgFolder, forKey: .jpgFolder)
        try c.encode(keepRateTarget, forKey: .keepRateTarget)
        try c.encode(jobBrief, forKey: .jobBrief)
        try c.encode(editProfile, forKey: .editProfile)
        try c.encode(tasteSourceCount, forKey: .tasteSourceCount)
        try c.encode(tasteStrength, forKey: .tasteStrength)
        try c.encode(photos, forKey: .photos)
        try c.encode(collections, forKey: .collections)
        try c.encodeIfPresent(cursorPhotoID, forKey: .cursorPhotoID)
        try c.encode(decisionLedger, forKey: .decisionLedger)
        try c.encode(auditSeedPhotoIDs, forKey: .auditSeedPhotoIDs)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(shootID, forKey: .shootID)
        try c.encodeIfPresent(finalSetOrder, forKey: .finalSetOrder)
        try c.encodeIfPresent(exportHistory, forKey: .exportHistory)
        try c.encodeIfPresent(batchHistory, forKey: .batchHistory)
        try c.encodeIfPresent(workspaceRestore, forKey: .workspaceRestore)
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
    /// Path/proxy refine only — safe to merge into a live session.
    case photosUpdated([PhotoRecord])
    /// Cluster/tier reshape from embed+score — apply only at a session boundary.
    case refinementReady([PhotoRecord])
    case finished(LuminaProject)
    case failed(String)
}
