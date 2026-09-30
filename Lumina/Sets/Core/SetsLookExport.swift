import CoreImage
import Foundation

/// Export's renders (`SetsExportJob.Item.look`) through the same `LookPipeline` the previews use,
/// at full size, with the export settings the roadmap asks for (§7): no intermediate caching, a
/// 512 MB memory target on a Mac with 8 GB or less, one render at a time (the job runs its items
/// in order). RAW 9 §2: the shoot's pinned decoder version when the body supports it, else the
/// fastest; a RAW 9 failure (an error, or more than 8 s at export size) re-renders that one file
/// with the previous version, once, and says so in the result.
nonisolated enum SetsLookExport {
    nonisolated(unsafe) private static var _pipeline: LookPipeline?
    private static let lock = NSLock()

    struct Timeout: Error, CustomStringConvertible { let seconds: Double; var description: String { "took more than \(Int(seconds)) s" } }

    /// What the render used, for the export's result block.
    struct Outcome: Equatable, Sendable {
        var decoder: Int?
        var fellBackFrom: Int?
        var reason: String?
        var ms: Double = 0
        var label: String { decoder.map { "raw \($0)" + (fellBackFrom.map { f in " (raw \(f) failed: \(reason ?? "error"))" } ?? "") } ?? "embedded image" }
    }

    static func pipeline() throws -> LookPipeline {
        lock.lock(); defer { lock.unlock() }
        if let p = _pipeline { return p }
        let p = try LookPipeline(rules: LookRules.bundled(), cacheIntermediates: false,
                                 memoryLimitMB: LookRawPolicy.exportMemoryLimitMB(physicalMemory: ProcessInfo.processInfo.physicalMemory))
        _pipeline = p
        return p
    }

    /// `px` nil = full size. `format`: "tif"/"tiff" → 16-bit sRGB TIFF, anything else → JPEG 0.92.
    static func render(raw url: URL, look: String, px: Int?, format: String) throws -> Data {
        try render(raw: url, look: look, px: px, format: format, decoder: nil).0
    }

    /// With the decoder version to use (`nil` = Core Image's default; the caller resolves the
    /// shoot's pin per body) and the outcome. A failure with `decoder` set falls back one version.
    static func render(raw url: URL, look: String, px: Int?, format: String, decoder: Int?, timeout: TimeInterval = LookRawPolicy.exportTimeout) throws -> (Data, Outcome) {
        let pipe = try pipeline()
        let parsed = try Look.parse(look)
        var outcome = Outcome(decoder: LookPipeline.isRAW(url) ? decoder : nil)
        let t0 = Date()
        do {
            let data = try timed(timeout, decoder != nil) { try encode(pipe, parsed, url: url, px: px, format: format, decoder: decoder) }
            outcome.ms = Date().timeIntervalSince(t0) * 1000
            return (data, outcome)
        } catch {
            guard let v = decoder, let prev = LookRawPolicy.fallback(after: v, supported: LookPipeline.supportedDecoderVersions(url: url)) else { throw error }
            NSLog("Lumina export: RAW decoder \(v) failed for \(url.lastPathComponent) (\(error)); rendering again with \(prev)")
            let data = try encode(pipe, parsed, url: url, px: px, format: format, decoder: prev)
            outcome.decoder = prev; outcome.fellBackFrom = v; outcome.reason = "\(error)"
            outcome.ms = Date().timeIntervalSince(t0) * 1000
            return (data, outcome)
        }
    }

    private static func encode(_ pipe: LookPipeline, _ look: Look, url: URL, px: Int?, format: String, decoder: Int?) throws -> Data {
        let dev = try LookPipeline.developAny(url: url, longEdge: px, rules: pipe.rules, decoderVersion: decoder, nr: look.nr)
        let img = pipe.apply(look, to: dev)
        switch format.lowercased() {
        case "tif", "tiff": return try pipe.tiff16(img, space: .sRGB)
        case "png": return try pipe.png(img, space: .sRGB)
        default: return try pipe.jpeg(img, quality: 0.92, space: .sRGB)
        }
    }

    /// Runs `work` on its own thread and waits at most `seconds` when `guarded`; a render that
    /// overruns keeps going in the background (Core Image can't be stopped mid-way) and its
    /// result is dropped. The fallback render then starts serially.
    static func timed(_ seconds: TimeInterval, _ guarded: Bool, _ work: @escaping () throws -> Data) throws -> Data {
        guard guarded, seconds > 0 else { return try work() }
        let box = ResultBox()
        let sem = DispatchSemaphore(value: 0)
        let t = Thread {
            box.set(Result { try work() })
            sem.signal()
        }
        t.qualityOfService = .utility
        t.start()
        guard sem.wait(timeout: .now() + seconds) == .success, let r = box.get() else { throw Timeout(seconds: seconds) }
        return try r.get()
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result<Data, Error>?
        func set(_ r: Result<Data, Error>) { lock.withLock { value = r } }
        func get() -> Result<Data, Error>? { lock.withLock { value } }
    }
}
