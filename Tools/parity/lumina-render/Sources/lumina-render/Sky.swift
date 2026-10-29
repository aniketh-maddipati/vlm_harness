import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// The sky mask for the blue-skies prototype (LookSky), the way the app finds it (`SetsMasks`):
/// Vision's scene classifier as the gate (`LookMasks.skyScore`), then `LookMasks.sky` on an sRGB
/// picture at most 1024 px. The app reads the RAW's embedded JPEG; this tool has the develop, so
/// it renders the look-free base instead (the same scene, Lumina's colour rather than the camera's).
enum SkyMask {
    struct Result {
        var found: [LookMasks.Found]
        var plane: LookMasks.Plane?
        var gate: Float?          // the best sky label's confidence, nil when no sky label passes
        var labels: [String: Float]
    }

    static func find(_ pipe: LookPipeline, _ dev: LookPipeline.Developed, gate: Bool = true) throws -> Result {
        let long = max(dev.extent.width, dev.extent.height)
        let scale = min(1, 1024 / long)
        let img = pipe.output(dev.image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        guard let cg = pipe.context.createCGImage(img, from: img.extent.integral, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw LookPipeline.Failure("sky: render failed")
        }
        let labels = scene(cg) ?? [:]
        let score = LookMasks.skyScore(labels)
        guard !gate || score != nil, let c = rgb(cg), let mask = LookMasks.sky(red: c.red, green: c.green, blue: c.blue) else {
            return Result(found: [], plane: nil, gate: score.map(Float.init), labels: labels)
        }
        let region = LookMasks.Region(mask: mask, score: score ?? 1, saliency: nil)
        return Result(found: LookMasks.name(people: [], objects: [], sky: region).filter { $0.id == "sky" }, plane: mask, gate: score.map(Float.init), labels: labels)
    }

    static func scene(_ image: CGImage) -> [String: Float]? {
        let request = VNClassifyImageRequest()
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return nil }
        var out: [String: Float] = [:]
        for o in request.results ?? [] { out[o.identifier] = max(out[o.identifier] ?? 0, o.confidence) }
        return out
    }

    static func rgb(_ image: CGImage) -> (red: LookMasks.Plane, green: LookMasks.Plane, blue: LookMasks.Plane)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self), row = ctx.bytesPerRow
        var r = LookMasks.Plane(width: w, height: h), g = r, b = r
        for y in 0..<h {
            for x in 0..<w {
                let o = y * row + 4 * x, i = y * w + x
                r.values[i] = Float(bytes[o]) / 255; g.values[i] = Float(bytes[o + 1]) / 255; b.values[i] = Float(bytes[o + 2]) / 255
            }
        }
        return (r, g, b)
    }

    /// A plane as an 8-bit grey PNG, row 0 at the top.
    static func writePNG(_ p: LookMasks.Plane, to url: URL) throws {
        var bytes = p.values.map { UInt8(max(0, min(255, ($0 * 255).rounded()))) }
        let cg = bytes.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: p.width, height: p.height, bitsPerComponent: 8, bytesPerRow: p.width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            return ctx.makeImage()
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let cg, let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw LookPipeline.Failure("mask PNG failed") }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw LookPipeline.Failure("mask PNG failed") }
    }
}
