import CoreImage
import Foundation

/// Export's renders (`SetsExportJob.Item.look`) through the same `LookPipeline` the previews use,
/// at full size, with the export settings the roadmap asks for (§7): no intermediate caching, a
/// 512 MB memory target, one render at a time (the job runs its items in order).
nonisolated enum SetsLookExport {
    nonisolated(unsafe) private static var _pipeline: LookPipeline?
    private static let lock = NSLock()

    static func pipeline() throws -> LookPipeline {
        lock.lock(); defer { lock.unlock() }
        if let p = _pipeline { return p }
        let p = try LookPipeline(rules: LookRules.bundled(), cacheIntermediates: false, memoryLimitMB: 512)
        _pipeline = p
        return p
    }

    /// `px` nil = full size. `format`: "tif"/"tiff" → 16-bit sRGB TIFF, anything else → JPEG 0.92.
    static func render(raw url: URL, look: String, px: Int?, format: String) throws -> Data {
        let pipe = try pipeline()
        let parsed = try Look.parse(look)
        let dev = try LookPipeline.developAny(url: url, longEdge: px, rules: pipe.rules)
        let img = pipe.apply(parsed, to: dev)
        switch format.lowercased() {
        case "tif", "tiff": return try pipe.tiff16(img, space: .sRGB)
        case "png": return try pipe.png(img, space: .sRGB)
        default: return try pipe.jpeg(img, quality: 0.92, space: .sRGB)
        }
    }
}
