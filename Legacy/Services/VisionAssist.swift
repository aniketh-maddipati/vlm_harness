// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Premium Vision assist for develop — face-aware auto tone, attention
/// saliency for subject protection, and face-avoiding heal donor placement.
/// All analysis runs off the main actor on a downsampled proxy.
enum VisionAssist {
    struct SubjectMap: Sendable {
        /// Normalized face boxes (Vision coords: origin bottom-left).
        var faces: [CGRect]
        /// Attention saliency peak in normalized image coords (origin top-left for UI).
        var attentionPeak: CGPoint?
        /// True when at least one face was detected.
        var hasFace: Bool { !faces.isEmpty }
    }

    /// Face + attention map for a photograph. Nil when the proxy cannot be loaded.
    static func subjectMap(imagePath: String) async -> SubjectMap? {
        await Task.detached(priority: .userInitiated) { () -> SubjectMap? in
            guard let cg = thumbnail(path: imagePath, maxSide: 768) else { return nil }
            let faces = detectFaces(in: cg)
            let peak = attentionPeak(in: cg)
            return SubjectMap(faces: faces, attentionPeak: peak)
        }.value
    }

    /// Face-weighted auto suggestion — exposure anchored on the face region
    /// when present, otherwise falls back to whole-frame histogram AutoDevelop.
    static func suggest(imagePath: String) async -> AutoDevelop.Suggestion? {
        async let base = AutoDevelop.suggest(imagePath: imagePath)
        async let map = subjectMap(imagePath: imagePath)
        guard var suggestion = await base else { return nil }
        guard let map, map.hasFace, let cg = thumbnail(path: imagePath, maxSide: 256) else {
            return suggestion
        }
        // Re-anchor exposure on the largest face so skin tones stay protected.
        if let face = map.faces.max(by: { $0.width * $0.height < $1.width * $1.height }),
           let faceMedian = luminanceMedian(in: cg, visionBox: face) {
            let faceExposure = clamp(log2(0.45 / max(faceMedian, 0.01)), -1.2, 1.2)
            // Blend: 70% face-anchored, 30% frame — never fight the whole-frame read.
            suggestion.exposure = faceExposure * 0.70 + suggestion.exposure * 0.30
            // Slightly softer contrast when faces dominate (skin prefers gentle grade).
            suggestion.contrast = min(suggestion.contrast, 18)
        }
        return suggestion
    }

    /// Prefer a heal donor that does not land on a face. Falls back to the
    /// geometric default when Vision finds nothing to avoid.
    static func healDonor(
        for spot: (x: Double, y: Double, radius: Double),
        imagePath: String?
    ) async -> (dx: Double, dy: Double) {
        let geometric = geometricDonor(x: spot.x, y: spot.y, radius: spot.radius)
        guard let imagePath, let map = await subjectMap(imagePath: imagePath), map.hasFace else {
            return geometric
        }
        // Try several candidate offsets; pick the first that clears all faces.
        let candidates: [(Double, Double)] = [
            geometric,
            (spot.radius * 2.5, 0),
            (-spot.radius * 2.5, 0),
            (0, spot.radius * 2.5),
            (0, -spot.radius * 2.5),
            (spot.radius * 2.2, spot.radius * 1.4),
            (-spot.radius * 2.2, spot.radius * 1.4),
        ]
        for (dx, dy) in candidates {
            let sx = spot.x + dx, sy = spot.y + dy
            guard sx > 0.02, sx < 0.98, sy > 0.02, sy < 0.98 else { continue }
            if !hitsFace(x: sx, y: sy, radius: spot.radius, faces: map.faces) {
                return (dx, dy)
            }
        }
        return geometric
    }

    // MARK: - Vision primitives

    private static func detectFaces(in cg: CGImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            return request.results?.map(\.boundingBox) ?? []
        } catch {
            return []
        }
    }

    private static func attentionPeak(in cg: CGImage) -> CGPoint? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first as? VNSaliencyImageObservation,
                  let objects = observation.salientObjects,
                  let best = objects.max(by: { $0.confidence < $1.confidence }) else {
                return nil
            }
            // Vision bottom-left → UI top-left.
            let box = best.boundingBox
            return CGPoint(x: box.midX, y: 1 - box.midY)
        } catch {
            return nil
        }
    }

    private static func hitsFace(x: Double, y: Double, radius: Double, faces: [CGRect]) -> Bool {
        // Spot is UI top-left; Vision boxes are bottom-left.
        let vy = 1 - y
        for face in faces {
            let inflated = face.insetBy(dx: -CGFloat(radius), dy: -CGFloat(radius))
            if inflated.contains(CGPoint(x: x, y: vy)) { return true }
        }
        return false
    }

    private static func geometricDonor(x: Double, y: Double, radius: Double) -> (Double, Double) {
        let direction: Double = x < 0.5 ? 1 : -1
        var dx = direction * radius * 2.2
        var dy = 0.0
        if x + dx < 0.02 || x + dx > 0.98 {
            dx = 0
            dy = (y < 0.5 ? 1 : -1) * radius * 2.2
        }
        return (dx, dy)
    }

    private static func luminanceMedian(in cg: CGImage, visionBox: CGRect) -> Double? {
        let w = cg.width, h = cg.height
        guard w > 2, h > 2 else { return nil }
        // Vision bottom-left → pixel top-left.
        let px = Int(visionBox.minX * CGFloat(w))
        let py = Int((1 - visionBox.maxY) * CGFloat(h))
        let pw = max(Int(visionBox.width * CGFloat(w)), 2)
        let ph = max(Int(visionBox.height * CGFloat(h)), 2)
        let x0 = max(0, min(px, w - 1))
        let y0 = max(0, min(py, h - 1))
        let x1 = max(x0 + 1, min(x0 + pw, w))
        let y1 = max(y0 + 1, min(y0 + ph, h))

        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &buffer, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var lumas: [Double] = []
        lumas.reserveCapacity((x1 - x0) * (y1 - y0))
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * w + x) * 4
                let r = Double(buffer[i]) / 255
                let g = Double(buffer[i + 1]) / 255
                let b = Double(buffer[i + 2]) / 255
                lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
            }
        }
        guard !lumas.isEmpty else { return nil }
        lumas.sort()
        return lumas[lumas.count / 2]
    }

    private static func thumbnail(path: String, maxSide: Int) -> CGImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}
