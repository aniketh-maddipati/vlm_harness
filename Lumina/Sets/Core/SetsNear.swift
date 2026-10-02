import CoreGraphics
import Foundation
import ImageIO
import Vision

/// How alike two photos are, for the page's retake stacks (DESIGN-ASKS Prompt 2 C): the distance
/// between Vision's image feature prints of their embedded previews. 0 is the same image, about 1
/// is unrelated. Never a RAW decode: the bytes are the preview `SetsIngest` already reads for the
/// grid, so a pulled card stops this as it stops every other read.
///
/// The measure is pinned to one feature print revision, because the vectors (and with them the
/// threshold) change between revisions. `limit` is the threshold measured for that revision on
/// 277 hand-marked pairs, with this code's own distances: 93 % of the pairs under it are the same
/// picture (88–97) and 59 % of the retakes are under it (51–67). The page gets it as
/// `lumina.nearLimit` rather than carrying a number of its own.
///
/// Thread-safe. Measures run two at a time at `.utility`, one per photo however many pairs ask.
nonisolated final class SetsNear: @unchecked Sendable {
    /// The feature print revision the threshold was measured with (768 floats, macOS 14+).
    static let revision = VNGenerateImageFeaturePrintRequestRevision2
    /// The preview's long edge when it is measured, as in the measurement behind `limit`.
    static let pixels = 512

    /// The threshold for a revision, nil for one nobody has measured: the page then keeps its own rule.
    static func limit(for revision: Int) -> Double? { revision == VNGenerateImageFeaturePrintRequestRevision2 ? 0.35 : nil }
    static var limit: Double? { limit(for: revision) }

    /// Euclidean distance, as the threshold was measured. Nil when the vectors don't match in size.
    static func distance(_ a: [Float], _ b: [Float]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var sum = 0.0
        for i in 0..<a.count { let d = Double(a[i]) - Double(b[i]); sum += d * d }
        return sum.squareRoot()
    }

    private let ingest: SetsIngest
    private let capacity: Int
    private let lock = NSLock()
    private var vectors: [SetsIngest.Preview: [Float]] = [:]
    private var order: [SetsIngest.Preview] = []                     // oldest first
    private var waiting: [SetsIngest.Preview: [([Float]?) -> Void]] = [:]
    private let queue = OperationQueue()
    private(set) var measured = 0

    /// `capacity`: vectors kept (3 KB each; the default is about 24 MB, more than any card holds).
    init(ingest: SetsIngest, capacity: Int = 8000) {
        self.ingest = ingest
        self.capacity = max(2, capacity)
        queue.name = "lumina.near"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
    }

    /// The distance between two photos' previews, nil when either can't be measured (no preview,
    /// the card is out, Vision refuses).
    func distance(_ a: SetsIngest.Preview, _ b: SetsIngest.Preview) async -> Double? {
        async let va = vector(a), vb = vector(b)
        guard let x = await va, let y = await vb else { return nil }
        return Self.distance(x, y)
    }

    var count: Int { lock.withLock { vectors.count } }

    func vector(_ p: SetsIngest.Preview) async -> [Float]? {
        await withCheckedContinuation { (c: CheckedContinuation<[Float]?, Never>) in
            let start: Bool = lock.withLock {
                if let hit = vectors[p] { c.resume(returning: hit); return false }
                let first = waiting[p] == nil
                waiting[p, default: []].append { c.resume(returning: $0) }
                return first
            }
            guard start else { return }
            queue.addOperation { [weak self] in
                guard let self else { return }
                let v = self.measure(p)
                let callbacks: [([Float]?) -> Void] = self.lock.withLock {
                    if let v { self.store(p, v); self.measured += 1 }
                    return self.waiting.removeValue(forKey: p) ?? []
                }
                for f in callbacks { f(v) }
            }
        }
    }

    private func store(_ p: SetsIngest.Preview, _ v: [Float]) {
        if vectors.updateValue(v, forKey: p) == nil { order.append(p) }
        while order.count > capacity { vectors.removeValue(forKey: order.removeFirst()) }
    }

    private func measure(_ p: SetsIngest.Preview) -> [Float]? {
        guard !ingest.isGone(p.rel), let jpeg = try? ingest.preview(p) else { return nil }
        return Self.featurePrint(jpeg: jpeg)
    }

    /// The feature print of an upright JPEG, measured at `pixels` on the long edge.
    static func featurePrint(jpeg: Data) -> [Float]? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: pixels]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return featurePrint(image)
    }

    static func featurePrint(_ image: CGImage) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = revision
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil,
              let obs = request.results?.first as? VNFeaturePrintObservation, obs.elementType == .float else { return nil }
        return obs.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
