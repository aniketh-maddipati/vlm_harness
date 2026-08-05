import CoreGraphics
import Foundation

/// Explicit invalidation domains derived from `EditRecipe`.
///
/// Changing `LookIntent` must not rerun RAW decoding when a compatible RAW-stage
/// surface is cached. Changing `RawIntent` invalidates the RAW-stage surface and
/// everything downstream.
///
/// `EditRecipe` remains the single stored source of truth; intents are derived
/// views used for cache keys and stage application.

/// RAW-domain settings applied on `CIRAWFilter` before demosaic output.
struct RawIntent: Hashable, Sendable {
    /// EV applied in RAW domain (`CIRAWFilter.exposure`).
    var exposureEV: Double
    /// Target neutral temperature in Kelvin. 6500 + tint 0 means "as shot".
    var temperature: Double
    var tint: Double
    /// crs-style 0…100 — mapped onto `luminanceNoiseReductionAmount` when supported.
    var luminanceNR: Double
    /// crs-style 0…150 — mapped onto `sharpnessAmount` when supported.
    var sharpness: Double

    static let neutral = RawIntent(exposureEV: 0, temperature: 6500, tint: 0, luminanceNR: 0, sharpness: 0)

    /// "As shot" means the photographer has not overridden white balance.
    var isAsShotWhiteBalance: Bool {
        abs(temperature - 6500) <= 1 && abs(tint) <= 0.01
    }

    var fingerprint: String {
        String(format: "raw|%.5f|%.1f|%.3f|%.3f|%.3f", exposureEV, temperature, tint, luminanceNR, sharpness)
    }
}

/// Post-RAW scene-linear look operations — honestly implemented subset only.
struct LookIntent: Hashable, Sendable {
    var contrast: Double
    var highlights: Double
    var shadows: Double
    var vibrance: Double
    var saturation: Double

    static let neutral = LookIntent(contrast: 0, highlights: 0, shadows: 0, vibrance: 0, saturation: 0)

    var isNeutral: Bool { self == .neutral }

    var fingerprint: String {
        String(format: "look|%.4f|%.4f|%.4f|%.4f|%.4f", contrast, highlights, shadows, vibrance, saturation)
    }
}

/// Orientation, crop and presentation geometry.
struct GeometryIntent: Hashable, Sendable {
    var crop: EditCrop?
    var straightenDegrees: Double

    static let identity = GeometryIntent(crop: nil, straightenDegrees: 0)

    var fingerprint: String {
        "geo|\(crop?.fingerprint ?? "nocrop")|" + String(format: "%.3f", straightenDegrees)
    }
}

/// Display or export destination.
enum OutputIntent: String, Hashable, Sendable {
    /// Convert once to the active display profile at presentation.
    case display
    /// 16-bit ProPhoto RGB handoff TIFF.
    case exportProPhotoTIFF
    /// sRGB 8-bit JPEG.
    case exportSRGBJPEG

    var fingerprint: String { "out|\(rawValue)" }
}

extension EditRecipe {
    /// RAW-domain slice — invalidates the RAW-stage surface when changed.
    var rawIntent: RawIntent {
        RawIntent(
            exposureEV: exposure,
            temperature: temperature,
            tint: tint,
            luminanceNR: luminanceNR,
            sharpness: sharpness
        )
    }

    /// Post-RAW look slice. Whites/blacks/clarity/texture/dehaze are deliberately
    /// absent: their algorithms are not defensible and the controls are disabled.
    /// Stored values migrate forward but are not rendered.
    var lookIntent: LookIntent {
        LookIntent(
            contrast: contrast,
            highlights: highlights,
            shadows: shadows,
            vibrance: vibrance,
            saturation: saturation
        )
    }

    var geometryIntent: GeometryIntent {
        GeometryIntent(crop: crop, straightenDegrees: straightenDegrees)
    }
}
