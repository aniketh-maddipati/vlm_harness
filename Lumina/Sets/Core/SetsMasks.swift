import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

/// The selections Lumina finds in a photo by itself (`lumina.masks`, DESIGN-ASKS Prompt 28): the
/// subject, each person, each other object and the background, so Edit can offer them before
/// anyone draws. Vision finds them on the embedded preview, never a RAW decode, as `SetsNear`
/// measures: the bytes are the preview `SetsIngest` already reads, so a pulled card stops this
/// as it stops every other read. The maths around Vision's answer (edge refinement against the
/// photo, outlines, naming) is `LookMasks`.
///
/// Finders (macOS 14+, all on the Mac): `VNGeneratePersonInstanceMaskRequest` (up to four people),
/// `VNGenerateForegroundInstanceMaskRequest` (the salient objects, people included) and
/// `VNGenerateAttentionBasedSaliencyImageRequest` (which of them stands out). Sky and the
/// landscape classes need a model of their own and come later.
///
/// Thread-safe. One photo at a time at `.utility`, one finding per photo however many ask.
nonisolated final class SetsMasks: @unchecked Sendable {
    /// The preview's long edge when masks are found: Vision's masks come back at this size, and
    /// the outline's precision is one pixel of it.
    static let pixels = 1024

    private let ingest: SetsIngest
    private let capacity: Int
    private let lock = NSLock()
    private var found: [SetsIngest.Preview: [LookMasks.Found]] = [:]
    private var order: [SetsIngest.Preview] = []                     // oldest first
    private var waiting: [SetsIngest.Preview: [([LookMasks.Found]?) -> Void]] = [:]
    private let queue = OperationQueue()
    private(set) var measured = 0

    /// `capacity`: photos whose masks are kept (outlines only, a few KB each).
    init(ingest: SetsIngest, capacity: Int = 4000) {
        self.ingest = ingest
        self.capacity = max(1, capacity)
        queue.name = "lumina.masks"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
    }

    var count: Int { lock.withLock { found.count } }

    /// The masks found in a photo, nil when it can't be read (no preview, the card is out, Vision
    /// refuses). An empty list is a photo with nothing to select.
    func masks(_ p: SetsIngest.Preview) async -> [LookMasks.Found]? {
        await withCheckedContinuation { (c: CheckedContinuation<[LookMasks.Found]?, Never>) in
            let start: Bool = lock.withLock {
                if let hit = found[p] { c.resume(returning: hit); return false }
                let first = waiting[p] == nil
                waiting[p, default: []].append { c.resume(returning: $0) }
                return first
            }
            guard start else { return }
            queue.addOperation { [weak self] in
                guard let self else { return }
                let f = self.measure(p)
                let callbacks: [([LookMasks.Found]?) -> Void] = self.lock.withLock {
                    if let f { self.store(p, f); self.measured += 1 }
                    return self.waiting.removeValue(forKey: p) ?? []
                }
                for cb in callbacks { cb(f) }
            }
        }
    }

    private func store(_ p: SetsIngest.Preview, _ f: [LookMasks.Found]) {
        if found.updateValue(f, forKey: p) == nil { order.append(p) }
        while order.count > capacity { found.removeValue(forKey: order.removeFirst()) }
    }

    private func measure(_ p: SetsIngest.Preview) -> [LookMasks.Found]? {
        guard !ingest.isGone(p.rel), let jpeg = try? ingest.preview(p) else { return nil }
        return Self.masks(jpeg: jpeg)
    }

    /// The masks in an upright JPEG, found at `pixels` on the long edge.
    static func masks(jpeg: Data) -> [LookMasks.Found]? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: pixels]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return masks(image)
    }

    /// The masks in a picture. `refine`: snap each mask's edge to the picture's own edges
    /// (`LookMasks.guided`) before outlining it.
    static func masks(_ image: CGImage, refine: Bool = true) -> [LookMasks.Found]? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let people = VNGeneratePersonInstanceMaskRequest()
        let objects = VNGenerateForegroundInstanceMaskRequest()
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        // Each on its own: one finder failing (or unsupported on this Mac) leaves the others.
        let peopleRan = (try? handler.perform([people])) != nil
        let objectsRan = (try? handler.perform([objects])) != nil
        guard peopleRan || objectsRan else { return nil }
        _ = try? handler.perform([saliency])

        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        let guide = refine ? luminance(image) : nil
        let salient = saliency.results?.first.flatMap { plane($0.pixelBuffer) }.map { LookMasks.resized($0, width: w, height: h) }

        func regions(_ obs: VNInstanceMaskObservation?) -> [LookMasks.Region] {
            guard let obs else { return [] }
            return obs.allInstances.compactMap { i -> LookMasks.Region? in
                guard let buffer = try? obs.generateScaledMaskForImage(forInstances: IndexSet(integer: i), from: handler),
                      var mask = plane(buffer) else { return nil }
                if mask.width != w || mask.height != h { mask = LookMasks.resized(mask, width: w, height: h) }
                if let guide { mask = LookMasks.guided(mask, guide: guide, radius: max(2, max(w, h) / 128)) }
                return LookMasks.Region(mask: mask, score: Double(obs.confidence), saliency: salient.map { LookMasks.mean($0, inside: mask) })
            }
        }
        return LookMasks.name(people: regions(peopleRan ? people.results?.first : nil),
                              objects: regions(objectsRan ? objects.results?.first : nil))
    }

    /// A one-channel pixel buffer (Vision's masks are 32-bit float, 0 … 1; 8-bit read as /255).
    static func plane(_ buffer: CVPixelBuffer) -> LookMasks.Plane? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
        guard w > 0, h > 0 else { return nil }
        var p = LookMasks.Plane(width: w, height: h)
        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_OneComponent32Float:
            for y in 0..<h {
                let r = base.advanced(by: y * row).assumingMemoryBound(to: Float.self)
                for x in 0..<w { p.values[y * w + x] = min(1, max(0, r[x])) }
            }
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<h {
                let r = base.advanced(by: y * row).assumingMemoryBound(to: UInt8.self)
                for x in 0..<w { p.values[y * w + x] = Float(r[x]) / 255 }
            }
        default:
            return nil
        }
        return p
    }

    /// The picture's luminance, 0 … 1, at its own size: the guide the masks' edges snap to.
    static func luminance(_ image: CGImage) -> LookMasks.Plane? {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self), row = ctx.bytesPerRow
        var p = LookMasks.Plane(width: w, height: h)
        for y in 0..<h { for x in 0..<w { p.values[y * w + x] = Float(bytes[y * row + x]) / 255 } }
        return p
    }
}
