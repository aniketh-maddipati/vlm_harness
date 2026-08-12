// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import Vision
import AppKit
import ImageIO

enum FaceDetector {
    struct Result {
        var hasFace: Bool
        var quality: Double
    }

    static func analyze(_ imageURL: URL) -> Result {
        guard let cg = loadCG(imageURL) else { return Result(hasFace: false, quality: 0) }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let faces = request.results, let best = faces.max(by: {
                $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
            }) else {
                return Result(hasFace: false, quality: 0)
            }
            let area = best.boundingBox.width * best.boundingBox.height
            let quality = min(max(area * 4.0, 0.2), 1.0)
            return Result(hasFace: true, quality: quality)
        } catch {
            return Result(hasFace: false, quality: 0)
        }
    }

    static func hasFace(in imageURL: URL) -> Bool {
        analyze(imageURL).hasFace
    }

    static func hasFace(in cgImage: CGImage) -> Bool {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return !(request.results?.isEmpty ?? true)
        } catch {
            return false
        }
    }

    static func faceBounds(in cgImage: CGImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first?.boundingBox
        } catch {
            return nil
        }
    }

    private static func loadCG(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }
}
