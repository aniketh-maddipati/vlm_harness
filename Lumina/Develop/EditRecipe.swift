import CoreGraphics
import Foundation

/// Schema version for recipe serialization / future migration.
enum EditRecipeSchemaVersion: Int, Codable, Sendable, Comparable {
    case v1 = 1

    static let current: EditRecipeSchemaVersion = .v1

    static func < (lhs: EditRecipeSchemaVersion, rhs: EditRecipeSchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Semantic develop values — never rendered pixels.
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
    /// Clone-heal spots. Runtime-only on this type (persisted via DevelopRecipe);
    /// excluded from the v1 serialized schema, included in the render fingerprint.
    var retouch: [RetouchSpot] = []

    var sourceNeighbors: [String]
    var confidence: Double

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, exposure, temperature, tint, contrast, highlights,
             shadows, whites, blacks, texture, clarity, dehaze, vibrance, saturation,
             sharpness, luminanceNR, crop, straightenDegrees, sourceNeighbors, confidence
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
        self.sourceNeighbors = sourceNeighbors
        self.confidence = confidence
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

    /// Copy-on-write mutation helper — returns a new recipe with the same id.
    func updating(_ mutate: (inout EditRecipe) -> Void) -> EditRecipe {
        var copy = self
        mutate(&copy)
        return copy
    }

    /// New identity — used when forking a shared recipe into a private copy.
    func forked(id: UUID = UUID()) -> EditRecipe {
        var copy = forkedBase(id: id)
        copy.retouch = retouch
        return copy
    }

    private func forkedBase(id: UUID) -> EditRecipe {
        EditRecipe(
            id: id,
            schemaVersion: schemaVersion,
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
            sourceNeighbors: sourceNeighbors,
            confidence: confidence
        )
    }

    // MARK: - Bridging to legacy DevelopRecipe

    init(from legacy: DevelopRecipe, id: UUID = UUID()) {
        self.init(
            id: id,
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
            sourceNeighbors: legacy.sourceNeighbors,
            confidence: legacy.confidence
        )
        self.retouch = legacy.retouch
    }

    var asDevelopRecipe: DevelopRecipe {
        var legacy = asDevelopRecipeBase
        legacy.retouch = retouch
        return legacy
    }

    private var asDevelopRecipeBase: DevelopRecipe {
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
        var recipe = try decoder.decode(EditRecipe.self, from: data)
        recipe = migrate(recipe)
        return recipe
    }

    /// Forward-compatible migration hook. Unknown future versions clamp to known fields via Codable defaults.
    static func migrate(_ recipe: EditRecipe) -> EditRecipe {
        switch recipe.schemaVersion {
        case .v1:
            return recipe
        }
    }

    /// Fingerprint for cache keys — excludes volatile identity when comparing semantic equality of values.
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
        // CIImage extent origin may be non-zero; crop is relative to oriented bounds.
        let originX = extent.minX + CGFloat(c.x) * extent.width
        // Normalized y is top-down; CIImage y is bottom-up.
        let originY = extent.maxY - CGFloat(c.y + c.height) * extent.height
        return CGRect(
            x: originX,
            y: originY,
            width: CGFloat(c.width) * extent.width,
            height: CGFloat(c.height) * extent.height
        )
    }
}
