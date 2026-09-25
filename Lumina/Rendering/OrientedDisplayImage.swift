import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Single orientation contract for every photograph that reaches Metal.
///
/// EXIF is baked into pixels **once** by ImageIO (`CreateThumbnailWithTransform`).
/// The CIImage wrapper never applies orientation again. Metal's
/// `CIRenderDestination.isFlipped` is the only remaining Y conversion
/// (Core Image is bottom-left; the drawable is top-left).
///
/// Click-through used to seed the drawable with a lazy file-backed CIImage
/// that still carried a pending orientation transform. Combined with the Metal
/// flip that presents inverted for a frame, then ImageIO pixels replace it,
/// then an unoriented RAW demosaic can swap landscape/portrait — the
/// upside-down flash and glitch.
nonisolated enum OrientedDisplayImage {

    private static let rawExtensions: Set<String> = [
        "ARW", "CR2", "CR3", "NEF", "RAF", "DNG", "ORF", "RW2", "PEF", "SRW", "3FR", "IIQ",
    ]

    /// EXIF values that rotate the stored bitmap by 90° (width/height swap).
    static let swapDimensions: Set<UInt32> = [5, 6, 7, 8]

    struct FileOrientation: Equatable, Sendable {
        let pixelWidth: Int
        let pixelHeight: Int
        let orientation: UInt32

        var orientedSize: (width: Int, height: Int) {
            OrientedDisplayImage.orientedSize(
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                orientation: orientation
            )
        }
    }

    static func orientedSize(pixelWidth: Int, pixelHeight: Int, orientation: UInt32) -> (width: Int, height: Int) {
        if swapDimensions.contains(orientation) {
            return (pixelHeight, pixelWidth)
        }
        return (pixelWidth, pixelHeight)
    }

    static func fileOrientation(at url: URL) -> FileOrientation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard w > 0, h > 0 else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return FileOrientation(pixelWidth: w, pixelHeight: h, orientation: orientation)
    }

    /// ImageIO thumbnail with transform — pixels are already display-upright.
    static func cgImage(at url: URL, maxPixelSize: Int? = nil) -> CGImage? {
        let ext = url.pathExtension.uppercased()
        guard !rawExtensions.contains(ext) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let source: CGImageSource? = {
            if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                return CGImageSourceCreateWithData(data as CFData, nil)
            }
            return CGImageSourceCreateWithURL(url as CFURL, nil)
        }()
        guard let source else { return nil }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        if let maxPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Wrap pixels that already have EXIF baked in. Do not apply the file
    /// orientation tag a second time — that is the inverted first-frame path.
    static func ciImage(fromOrientedPixels image: CGImage) -> CIImage {
        normalizeOrigin(CIImage(cgImage: image))
    }

    static func ciImage(at url: URL, maxPixelSize: Int? = nil) -> CIImage? {
        guard let cg = cgImage(at: url, maxPixelSize: maxPixelSize) else { return nil }
        return ciImage(fromOrientedPixels: cg)
    }

    static func normalizeOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(
            translationX: -image.extent.origin.x,
            y: -image.extent.origin.y
        ))
    }

    /// If a decoder left pixels in sensor space, rotate once to the file's EXIF.
    /// No-op when extent already matches the oriented display size.
    static func aligning(_ image: CIImage, toFile url: URL) -> CIImage {
        guard let file = fileOrientation(at: url), file.orientation != 1 else {
            return normalizeOrigin(image)
        }
        let current = image.extent
        guard current.width > 1, current.height > 1 else { return normalizeOrigin(image) }

        let oriented = file.orientedSize
        let orientedLong = CGFloat(max(oriented.width, oriented.height))
        guard orientedLong > 0 else { return normalizeOrigin(image) }
        let scale = max(current.width, current.height) / orientedLong
        let expectedW = CGFloat(oriented.width) * scale
        let expectedH = CGFloat(oriented.height) * scale
        if abs(current.width - expectedW) <= 2, abs(current.height - expectedH) <= 2 {
            return normalizeOrigin(image)
        }

        let sensorLong = CGFloat(max(file.pixelWidth, file.pixelHeight))
        guard sensorLong > 0 else { return normalizeOrigin(image) }
        let sensorScale = max(current.width, current.height) / sensorLong
        let sensorW = CGFloat(file.pixelWidth) * sensorScale
        let sensorH = CGFloat(file.pixelHeight) * sensorScale
        guard abs(current.width - sensorW) <= 2, abs(current.height - sensorH) <= 2 else {
            return normalizeOrigin(image)
        }
        guard let orientation = CGImagePropertyOrientation(rawValue: file.orientation) else {
            return normalizeOrigin(image)
        }
        return normalizeOrigin(image.oriented(orientation))
    }

    /// Decode a preview file and put it up the right way using the orientation of
    /// the **source** it came out of.
    ///
    /// The embedded preview that `exiftool -b -PreviewImage` pulls out of a RAW is
    /// in sensor space and carries no orientation tag of its own. Every decode of
    /// such a file applies a transform that is a no-op, so a portrait frame stays
    /// on its side for as long as that file exists. The orientation belongs to the
    /// RAW, not to those bytes, so this is the one place that can bake it in.
    ///
    /// A preview that carries its own tag is left to the ordinary transform, and a
    /// preview already in the source's display shape is left alone — rotating an
    /// upright picture is the same bug facing the other way.
    static func uprightPreview(
        at previewURL: URL,
        fromSourceAt sourceURL: URL,
        maxPixelSize: Int? = nil
    ) -> (image: CGImage, rotated: Bool)? {
        guard let decoded = cgImage(at: previewURL, maxPixelSize: maxPixelSize) else { return nil }
        guard let file = fileOrientation(at: sourceURL), file.orientation != 1 else {
            return (decoded, false)
        }
        // The preview brought its own orientation; `cgImage` has applied it.
        if let preview = fileOrientation(at: previewURL), preview.orientation != 1 {
            return (decoded, false)
        }
        guard let orientation = CGImagePropertyOrientation(rawValue: file.orientation) else {
            return (decoded, false)
        }

        if swapDimensions.contains(file.orientation) {
            let oriented = file.orientedSize
            let sourceIsPortrait = oriented.height > oriented.width
            let previewIsPortrait = decoded.height > decoded.width
            // Already in the source's display shape — nothing left to apply.
            if sourceIsPortrait == previewIsPortrait { return (decoded, false) }
        }
        // Orientations 2, 3 and 4 do not change the shape, so there is nothing to
        // compare and the tagless preview is taken at its word: sensor space.
        // Same limit `OrientationContractTests` names for `aligning`.

        let turned = CIImage(cgImage: decoded).oriented(orientation)
        guard let baked = bakingContext.createCGImage(turned, from: turned.extent) else {
            return (decoded, false)
        }
        return (baked, true)
    }

    /// Only ever used to bake an orientation into a preview being written to disk.
    private static let bakingContext = CIContext(options: [.useSoftwareRenderer: false])

    struct DisplayFrame {
        let assetID: UUID
        let image: CIImage
        let recipe: EditRecipe?
        var layoutSize: CGSize
        let identity: DevelopSelectedImageIdentity?
        var generation: UInt64? = nil
        var preGeometryExtent: CGRect? = nil
        /// RAW-stage attribution for `image`. Measurement only — `select` never
        /// reads it, so frame selection is byte-for-byte what it was.
        var rawStageBacking: DevelopRawStageBacking = .unattributed
    }

    static func select(
        assetID: UUID,
        recipe: EditRecipe,
        promoted: DisplayFrame?,
        fallback: DisplayFrame?,
        retained: DisplayFrame?
    ) -> DisplayFrame? {
        let browse = fallback.flatMap { $0.assetID == assetID ? $0 : nil }
        let previous = retained.flatMap { $0.assetID == assetID ? $0 : nil }
        if var candidate = promoted,
           candidate.assetID == assetID,
           candidate.recipe?.valueFingerprint == recipe.valueFingerprint,
           matchesGeometry(candidate: candidate, fallback: browse?.image, recipe: recipe) {
            if let candidateGeneration = candidate.generation, let previousGeneration = previous?.generation,
               candidateGeneration < previousGeneration {
                return previous
            }
            if let previous, previous.recipe?.geometryIntent == recipe.geometryIntent {
                candidate.layoutSize = previous.layoutSize
            } else if let browse {
                candidate.layoutSize = DevelopRenderGraph.applyGeometry(recipe, to: browse.image).extent.size
            }
            return candidate
        }
        return previous ?? browse
    }

    private static func matchesGeometry(candidate: DisplayFrame, fallback: CIImage?, recipe: EditRecipe) -> Bool {
        guard let reference = candidate.preGeometryExtent else {
            return stablePresent(promoted: candidate.image, fallback: fallback, recipe: recipe) === candidate.image
        }
        guard validExtent(reference), validExtent(candidate.image.extent) else { return false }
        let source = CIImage(color: .clear).cropped(to: reference)
        let expected = DevelopRenderGraph.applyGeometry(recipe, to: source).extent
        guard validExtent(expected) else { return false }
        return candidate.image.extent.integral == expected.integral
    }

    private static func validExtent(_ extent: CGRect) -> Bool {
        extent.origin.x.isFinite && extent.origin.y.isFinite
            && extent.width.isFinite && extent.height.isFinite
            && extent.width > 0 && extent.height > 0
    }

    static func stablePresent(promoted: CIImage?, fallback: CIImage?, recipe: EditRecipe = .neutral) -> CIImage? {
        guard let promoted else { return fallback }
        guard let fallback else { return promoted }
        let expected = DevelopRenderGraph.applyGeometry(recipe, to: fallback).extent.size
        let actual = promoted.extent.size
        guard expected.width > 0, expected.height > 0, actual.width > 0, actual.height > 0 else {
            return fallback
        }
        let scale = max(actual.width, actual.height) / max(expected.width, expected.height)
        let roundingTolerance = 2 * max(1, scale)
        if abs(actual.width - expected.width * scale) > roundingTolerance
            || abs(actual.height - expected.height * scale) > roundingTolerance {
            return fallback
        }
        return promoted
    }
}
