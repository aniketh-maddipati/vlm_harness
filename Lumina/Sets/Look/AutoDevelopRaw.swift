import CoreImage
import Foundation

/// `ImageStats` from the RAW itself (BRIDGE-v0.02 §1): the file developed small through the same
/// `LookPipeline.develop` every preview and export starts from (the rules' rawDevelop, lens shading
/// and base match; no look), at `longEdge` px with Core Image's default decoder, the way the tone
/// anchor is measured, then read back as scene-linear floats in the rules' working space. Never the
/// embedded JPEG: that one carries the camera's own tone curve and picture profile.
///
/// Blocking (a RAW decode, tens of ms at 256 px): call it off the main thread.
nonisolated enum AutoDevelopRaw {
    static let longEdge = 256

    nonisolated(unsafe) private static var contexts: [String: CIContext] = [:]
    private static let lock = NSLock()

    static func stats(url: URL, rules: LookRules) throws -> ImageStats {
        guard LookPipeline.isRAW(url) else { throw LookPipeline.Failure("\(url.lastPathComponent): Auto reads RAWs only") }
        let dev = try LookPipeline.develop(url: url, longEdge: longEdge, rules: rules)
        let img = LookPipeline.atOrigin(LookPipeline.scaled(dev.image, longEdge: longEdge))
        let w = Int(img.extent.width.rounded(.down)), h = Int(img.extent.height.rounded(.down))
        guard w > 0, h > 0, !img.extent.isInfinite, let space = LookPipeline.colorSpace(named: rules.workingSpace) else {
            throw LookPipeline.Failure("\(url.lastPathComponent): nothing to measure")
        }
        let ctx: CIContext = lock.withLock {
            if let c = contexts[rules.workingSpace] { return c }
            let c = CIContext(options: [.workingColorSpace: space, .workingFormat: CIFormat.RGBAh.rawValue, .cacheIntermediates: false, .name: "AutoDevelopRaw"])
            contexts[rules.workingSpace] = c
            return c
        }
        var px = [Float](repeating: 0, count: w * h * 4)
        ctx.render(img, toBitmap: &px, rowBytes: w * 16, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: space)
        guard let stats = ImageStats.measure(linearRGBA: px, luma: rules.luma, nativeTemperature: dev.asShot.kelvin, nativeTint: dev.asShot.tint) else {
            throw LookPipeline.Failure("\(url.lastPathComponent): nothing to measure")
        }
        return stats
    }
}
