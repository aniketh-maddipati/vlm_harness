import CoreGraphics
import Foundation

/// Schema version for recipe serialization / migration.
enum EditRecipeSchemaVersion: Int, Codable, Sendable, Comparable {
    case v1 = 1
    /// Retouch spots participate in the serialized schema (were runtime-only in v1).
    case v2 = 2

    static let current: EditRecipeSchemaVersion = .v2

    static func < (lhs: EditRecipeSchemaVersion, rhs: EditRecipeSchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Canonical develop recipe for P0 — preview and export share this value.
/// Immutable value type; edits produce a new instance.
struct EditRecipe: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let schemaVersion: EditRecipeSchemaVersion

    /// Absolute Lightroom-compatible develop parameters.
    var exposure: Double
    /// Kelvin white balance (neutral ≈ 6500).
    var temperature: Double
    var tint: Double
    var contrast: Double
    var highlights: Double
    var shadows: Double
    var whites: Double
    var blacks: Double
    var texture: Double
    var clarity: Double
    var dehaze: Double
    var vibrance: Double
    var saturation: Double
    /// Amount 0…150 (crs:Sharpness). Applied only when platform filter is trustworthy.
    var sharpness: Double
    /// Amount 0…100 (crs:LuminanceSmoothing).
    var luminanceNR: Double
    /// Normalized crop in oriented image space (0…1). Nil = full frame.
    var crop: EditCrop?
    /// Clockwise rotation in degrees (−45…45 straighten + 90° multiples via orientation).
    var straightenDegrees: Double
    /// Clone-heal spots. Serialized from schema v2 onward.
    var retouch: [RetouchSpot]
    var sourceNeighbors: [String]
    var confidence: Double

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, exposure, temperature, tint, contrast, highlights,
             shadows, whites, blacks, texture, clarity, dehaze, vibrance, saturation,
             sharpness, luminanceNR, crop, straightenDegrees, retouch,
             sourceNeighbors, confidence
    }

    static let neutral = EditRecipe()

    init(
        id: UUID = UUID(),
        schemaVersion: EditRecipeSchemaVersion = .current,
        exposure: Double = 0,
        temperature: Double = 6500,
        tint: Double = 0,
        contrast: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        whites: Double = 0,
        blacks: Double = 0,
        texture: Double = 0,
        clarity: Double = 0,
        dehaze: Double = 0,
        vibrance: Double = 0,
        saturation: Double = 0,
        sharpness: Double = 0,
        luminanceNR: Double = 0,
        crop: EditCrop? = nil,
        straightenDegrees: Double = 0,
        retouch: [RetouchSpot] = [],
        sourceNeighbors: [String] = [],
        confidence: Double = 1
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
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
        self.crop = crop
        self.straightenDegrees = straightenDegrees
        self.retouch = retouch
        self.sourceNeighbors = sourceNeighbors
        self.confidence = confidence
    }

    /// Tolerant decoding — accepts v1 EditRecipe, legacy DevelopRecipe-shaped JSON, and partial blobs.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        if let version = try c.decodeIfPresent(EditRecipeSchemaVersion.self, forKey: .schemaVersion) {
            schemaVersion = version
        } else if let raw = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) {
            schemaVersion = EditRecipeSchemaVersion(rawValue: raw) ?? .v1
        } else {
            schemaVersion = .v1
        }
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 6500
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
        crop = try c.decodeIfPresent(EditCrop.self, forKey: .crop)
        straightenDegrees = try c.decodeIfPresent(Double.self, forKey: .straightenDegrees) ?? 0
        retouch = try c.decodeIfPresent([RetouchSpot].self, forKey: .retouch) ?? []
        sourceNeighbors = try c.decodeIfPresent([String].self, forKey: .sourceNeighbors) ?? []
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(exposure, forKey: .exposure)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(tint, forKey: .tint)
        try c.encode(contrast, forKey: .contrast)
        try c.encode(highlights, forKey: .highlights)
        try c.encode(shadows, forKey: .shadows)
        try c.encode(whites, forKey: .whites)
        try c.encode(blacks, forKey: .blacks)
        try c.encode(texture, forKey: .texture)
        try c.encode(clarity, forKey: .clarity)
        try c.encode(dehaze, forKey: .dehaze)
        try c.encode(vibrance, forKey: .vibrance)
        try c.encode(saturation, forKey: .saturation)
        try c.encode(sharpness, forKey: .sharpness)
        try c.encode(luminanceNR, forKey: .luminanceNR)
        try c.encodeIfPresent(crop, forKey: .crop)
        try c.encode(straightenDegrees, forKey: .straightenDegrees)
        try c.encode(retouch, forKey: .retouch)
        try c.encode(sourceNeighbors, forKey: .sourceNeighbors)
        try c.encode(confidence, forKey: .confidence)
    }

    var hasToneOrColorSettings: Bool {
        exposure != 0 || temperature != 6500 || tint != 0 || contrast != 0
            || highlights != 0 || shadows != 0 || whites != 0 || blacks != 0
            || texture != 0 || clarity != 0 || dehaze != 0 || vibrance != 0 || saturation != 0
            || sharpness != 0 || luminanceNR != 0
    }

    var hasGeometry: Bool {
        crop != nil || abs(straightenDegrees) > 0.01
    }

    var hasSettings: Bool {
        hasToneOrColorSettings || hasGeometry || !retouch.isEmpty
    }

    /// Copy-on-write mutation helper — returns a new recipe with the same id.
    func updating(_ mutate: (inout EditRecipe) -> Void) -> EditRecipe {
        var copy = self
        mutate(&copy)
        return copy
    }

    /// New identity — used when forking a shared recipe into a private copy.
    func forked(id: UUID = UUID()) -> EditRecipe {
        EditRecipe(
            id: id,
            schemaVersion: .current,
            exposure: exposure,
            temperature: temperature,
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
            saturation: saturation,
            sharpness: sharpness,
            luminanceNR: luminanceNR,
            crop: crop,
            straightenDegrees: straightenDegrees,
            retouch: retouch,
            sourceNeighbors: sourceNeighbors,
            confidence: confidence
        )
    }

    // MARK: - Bridging to legacy DevelopRecipe (taste / XMP / older UI)

    init(from legacy: DevelopRecipe, id: UUID = UUID()) {
        self.init(
            id: id,
            schemaVersion: .current,
            exposure: legacy.exposure,
            temperature: legacy.temperature == 0 ? 6500 : legacy.temperature,
            tint: legacy.tint,
            contrast: legacy.contrast,
            highlights: legacy.highlights,
            shadows: legacy.shadows,
            whites: legacy.whites,
            blacks: legacy.blacks,
            texture: legacy.texture,
            clarity: legacy.clarity,
            dehaze: legacy.dehaze,
            vibrance: legacy.vibrance,
            saturation: legacy.saturation,
            sharpness: legacy.sharpness,
            luminanceNR: legacy.luminanceNR,
            retouch: legacy.retouch,
            sourceNeighbors: legacy.sourceNeighbors,
            confidence: legacy.confidence
        )
    }

    /// Lossy toward legacy DevelopRecipe — geometry is not representable there.
    var asDevelopRecipe: DevelopRecipe {
        DevelopRecipe(
            exposure: exposure,
            temperature: temperature,
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
            saturation: saturation,
            sharpness: sharpness,
            luminanceNR: luminanceNR,
            retouch: retouch,
            sourceNeighbors: sourceNeighbors,
            confidence: confidence
        )
    }

    func applying(_ offsets: DevelopAdjustments) -> EditRecipe {
        updating { r in
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
        }
    }

    /// Merge tone/color from a legacy DevelopRecipe while preserving geometry.
    func replacingTone(from legacy: DevelopRecipe) -> EditRecipe {
        updating { r in
            r.exposure = legacy.exposure
            r.temperature = legacy.temperature == 0 ? 6500 : legacy.temperature
            r.tint = legacy.tint
            r.contrast = legacy.contrast
            r.highlights = legacy.highlights
            r.shadows = legacy.shadows
            r.whites = legacy.whites
            r.blacks = legacy.blacks
            r.texture = legacy.texture
            r.clarity = legacy.clarity
            r.dehaze = legacy.dehaze
            r.vibrance = legacy.vibrance
            r.saturation = legacy.saturation
            r.sharpness = legacy.sharpness
            r.luminanceNR = legacy.luminanceNR
            if !legacy.retouch.isEmpty {
                r.retouch = legacy.retouch
            }
            r.sourceNeighbors = legacy.sourceNeighbors
            r.confidence = legacy.confidence
        }
    }

    func offsets(from profile: EditRecipe) -> DevelopAdjustments {
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

    /// Scales extracted offsets from a baseline by taste strength (0…1.5). Geometry untouched.
    func withTasteStrength(_ strength: Double, baseline: EditRecipe = .neutral) -> EditRecipe {
        let t = min(max(strength, 0), 1.5)
        let u = 1 - t
        return updating { r in
            r.exposure = baseline.exposure * u + exposure * t
            r.temperature = baseline.temperature * u + temperature * t
            r.tint = baseline.tint * u + tint * t
            r.contrast = baseline.contrast * u + contrast * t
            r.highlights = baseline.highlights * u + highlights * t
            r.shadows = baseline.shadows * u + shadows * t
            r.whites = baseline.whites * u + whites * t
            r.blacks = baseline.blacks * u + blacks * t
            r.texture = baseline.texture * u + texture * t
            r.clarity = baseline.clarity * u + clarity * t
            r.dehaze = baseline.dehaze * u + dehaze * t
            r.vibrance = baseline.vibrance * u + vibrance * t
            r.saturation = baseline.saturation * u + saturation * t
            r.sharpness = baseline.sharpness * u + sharpness * t
            r.luminanceNR = baseline.luminanceNR * u + luminanceNR * t
            // Heal spots and geometry are binary user intent — never scaled.
            r.retouch = retouch
            r.crop = crop
            r.straightenDegrees = straightenDegrees
        }
    }

    func lrCalibrated() -> EditRecipe {
        let calibrated = asDevelopRecipe.lrCalibrated()
        return EditRecipe(from: calibrated, id: id).updating {
            $0.crop = crop
            $0.straightenDegrees = straightenDegrees
            $0.retouch = retouch
        }
    }

    // MARK: - Serialization

    /// Stable JSON for tests and on-disk persistence. Keys are sorted; doubles use finite encoding.
    static func encodeStable(_ recipe: EditRecipe) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .throw
        return try encoder.encode(recipe)
    }

    static func decode(_ data: Data) throws -> EditRecipe {
        let decoder = JSONDecoder()
        let recipe = try decoder.decode(EditRecipe.self, from: data)
        return migrate(recipe)
    }

    /// Forward-compatible migration hook.
    static func migrate(_ recipe: EditRecipe) -> EditRecipe {
        switch recipe.schemaVersion {
        case .v1, .v2:
            return recipe.withSchema(.current)
        }
    }

    private func withSchema(_ version: EditRecipeSchemaVersion) -> EditRecipe {
        EditRecipe(
            id: id,
            schemaVersion: version,
            exposure: exposure,
            temperature: temperature,
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
            saturation: saturation,
            sharpness: sharpness,
            luminanceNR: luminanceNR,
            crop: crop,
            straightenDegrees: straightenDegrees,
            retouch: retouch,
            sourceNeighbors: sourceNeighbors,
            confidence: confidence
        )
    }

    /// Fingerprint for cache keys — geometry and retouch invalidate caches.
    var valueFingerprint: String {
        let parts: [String] = [
            "v\(schemaVersion.rawValue)",
            fmt(exposure), fmt(temperature), fmt(tint), fmt(contrast),
            fmt(highlights), fmt(shadows), fmt(whites), fmt(blacks),
            fmt(texture), fmt(clarity), fmt(dehaze), fmt(vibrance), fmt(saturation),
            fmt(sharpness), fmt(luminanceNR), fmt(straightenDegrees),
            crop?.fingerprint ?? "nocrop",
            retouch.isEmpty ? "noheal" : retouch.map(\.fingerprint).joined(separator: ";"),
        ]
        return parts.joined(separator: "|")
    }

    private func fmt(_ v: Double) -> String {
        String(format: "%.5f", v)
    }
}

/// Normalized crop rectangle in oriented image coordinates (origin top-left, y down).
struct EditCrop: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = EditCrop(x: 0, y: 0, width: 1, height: 1)

    var isFullFrame: Bool {
        abs(x) < 1e-6 && abs(y) < 1e-6 && abs(width - 1) < 1e-6 && abs(height - 1) < 1e-6
    }

    var fingerprint: String {
        String(format: "%.5f,%.5f,%.5f,%.5f", x, y, width, height)
    }

    /// Clamp to unit square with positive size.
    func normalized() -> EditCrop {
        let w = min(max(width, 0.01), 1)
        let h = min(max(height, 0.01), 1)
        let nx = min(max(x, 0), 1 - w)
        let ny = min(max(y, 0), 1 - h)
        return EditCrop(x: nx, y: ny, width: w, height: h)
    }

    /// Map this normalized crop onto a pixel extent (same relative coords at any resolution).
    func pixelRect(in extent: CGRect) -> CGRect {
        let c = normalized()
        let originX = extent.minX + CGFloat(c.x) * extent.width
        let originY = extent.maxY - CGFloat(c.y + c.height) * extent.height
        return CGRect(
            x: originX,
            y: originY,
            width: CGFloat(c.width) * extent.width,
            height: CGFloat(c.height) * extent.height
        )
    }
}
