import CoreGraphics
import CoreImage
import Foundation

/// Documented color management contract for the develop engine.
///
/// Working space: linear extended-range scene-referred RGB approximated via
/// Core Image's default working space for CIRAWFilter / CIImage filters
/// (`extendedLinearSRGB` when available, else linear sRGB). Tone mapping and
/// display conversion happen **exactly once** at the end of the graph.
///
/// Output spaces:
/// - Display preview: display P3 when the display ICC permits, else sRGB
/// - JPEG export: sRGB, 8-bit
/// - TIFF handoff: 16-bit, Adobe RGB (1998) when available, else sRGB
///
/// Pixel formats:
/// - Intermediate CI: floating-point (CIContext default)
/// - Display blit: BGRA8 (ImagePixelFormat) after display conversion
/// - Export TIFF: 16-bit/component RGB, no alpha
/// - Export JPEG: 8-bit RGB, no alpha
///
/// Alpha: opaque photographs; straight alpha only if a matte is composed later.
///
/// Lossy boundaries (documented):
/// 1. Interactive pyramid long-edge cap (resolution loss)
/// 2. JPEG proxy fallback (8-bit, camera tone curve) — never authoritative
/// 3. Display conversion to 8-bit BGRA for Metal preview
/// 4. JPEG export quantization (q≈0.92)
/// 5. Any unavailable CIRAW control approximated by CI filters (see DEVELOP_ENGINE.md)
enum DevelopColorPolicy {
    /// Preferred linear working space for filter evaluation.
    static var workingColorSpace: CGColorSpace {
        if let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) {
            return linear
        }
        if let linear = CGColorSpace(name: CGColorSpace.linearSRGB) {
            return linear
        }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    static var displayColorSpace: CGColorSpace {
        if let p3 = CGColorSpace(name: CGColorSpace.displayP3) { return p3 }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    static var exportJPEGColorSpace: CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB)!
    }

    static var exportTIFFColorSpace: CGColorSpace {
        // Prefer Display P3 for wide-gamut handoff when Adobe RGB is unavailable as a named space.
        if let adobe = CGColorSpace(name: "kCGColorSpaceAdobeRGB1998" as CFString) {
            return adobe
        }
        if let p3 = CGColorSpace(name: CGColorSpace.displayP3) {
            return p3
        }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// CIContext options shared by preview and export — one working-space policy.
    static var ciContextOptions: [CIContextOption: Any] {
        [
            .workingColorSpace: workingColorSpace,
            .workingFormat: CIFormat.RGBAh,
            .cacheIntermediates: true,
            .useSoftwareRenderer: false,
        ]
    }

    static func describeColorSpace(_ space: CGColorSpace?) -> String {
        guard let space else { return "nil" }
        if let name = space.name as String? { return name }
        return "unnamed"
    }
}

/// Controls that the platform RAW/CI path cannot faithfully implement — omit rather than fake.
enum DevelopControlSupport: String, CaseIterable, Sendable {
    case exposure
    case temperature
    case tint
    case highlights
    case shadows
    case whites
    case blacks
    case contrast
    case crop
    case straighten
    case noiseReduction
    case sharpening
    case texture
    case clarity
    case dehaze
    case vibrance
    case saturation

    /// Whether Lumina applies this control with a documented, trustworthy mapping.
    var isTrusted: Bool {
        switch self {
        case .exposure, .temperature, .tint, .highlights, .shadows,
             .contrast, .vibrance, .saturation, .crop, .straighten,
             .sharpening, .noiseReduction, .whites, .blacks:
            return true
        case .texture, .clarity, .dehaze:
            // Approximations via unsharp / contrast — labeled as approximate in the lab.
            return true
        }
    }

    var approximationNote: String? {
        switch self {
        case .texture, .clarity:
            return "Approximated via CIUnsharpMask local contrast — not Lightroom Texture/Clarity."
        case .dehaze:
            return "Approximated via contrast/saturation lift — not a true dehaze model."
        case .whites, .blacks:
            return "Mapped through CIColorControls + tone curve endpoints — not crs White/Black sliders."
        case .noiseReduction:
            return "CINoiseReduction luminance path — not Lightroom Detail NR."
        case .sharpening:
            return "CISharpenLuminance / Unsharp — not Lightroom Detail sharpening."
        default:
            return nil
        }
    }
}
