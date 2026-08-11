// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import Foundation
import ImageIO
import CoreGraphics

/// Single-decode quality pass — sharpness + exposure from one thumbnail load.
enum PhotoScorer {
    struct Result: Sendable {
        var sharpness: Double
        var exposure: Double
        var aesthetic: Double
    }

    static func score(imageURL: URL) -> Result {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
            return Result(sharpness: 0, exposure: 0.5, aesthetic: 0.45)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            return Result(sharpness: 0, exposure: 0.5, aesthetic: 0.45)
        }
        return score(cgImage: cg)
    }

    static func score(cgImage: CGImage) -> Result {
        let sharpness = BlurScorer.score(cgImage: cgImage)
        let exposure = QualityScorer.exposureHealth(cgImage: cgImage)
        let aesthetic = min(max(0.45 + sharpness * 0.3 + exposure * 0.25, 0), 1)
        return Result(sharpness: sharpness, exposure: exposure, aesthetic: aesthetic)
    }
}
