import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Click to outline in the Skim Viewer (`lumina.video.prompt`, docs/masking/OUTLINING.md): the thing under a click,
/// outlined by Vision's prompted segmenter (`GenerateIterativeSegmentationRequest`, macOS 27). The first click starts
/// the outline; each click after it adds what's under it or takes it away. The request keeps the frame's encoding, so
/// on the mask lab's DAVIS frames the first click costs about 150 ms and each one after it 10–20 ms
/// (`Tools/masklab/iterative`). Where Vision's own finders merge touching things (the people in a group, a dog and
/// its owner), one click gives just the one meant: 0.27 IoU against 0.86 on the frames Vision merges
/// (`docs/masking/checkpoints/06-prompts-on-merged.jpg`).
///
/// The model is Apple's, downloaded by macOS the first time it is asked for (`DownloadableAssetsRequest`) into the
/// system's own storage, about 55 MB; Lumina sends nothing and reads nothing back but the model. One outline is held in
/// memory, for the page's frame and its clicks so far; a new frame, an undo or two minutes idle let it go.
nonisolated enum SkimPrompt {
    /// Whether this Mac can outline by clicks: "ready", "download" (macOS fetches the model at the first click),
    /// or "no" (before macOS 27, or the model can't be had).
    static func status() async -> String {
        guard #available(macOS 27.0, *) else { return "no" }
        return await Session.shared.status()
    }

    /// The outline for `points` on `frame` (a base64 JPEG the page drew from its own video), as one shape the page
    /// chooses like Vision's own (`LookMasks.Found`, id "pick"); nil when the frame or the clicks are not ones, or the
    /// model can't run. `key` names the frame: clicks on the same key add to the outline already made. `stroke`: a
    /// brush stroke over the thing (SkimFollow.promptStroke) seeds the outline in place of the first click.
    static func outline(key: String, frame: Any?, points: [SkimFollow.PromptPoint], stroke: [LookMasks.Point]? = nil) async -> LookMasks.Found? {
        guard #available(macOS 27.0, *) else { return nil }
        return await Session.shared.outline(key: key, frame: frame, points: points, stroke: stroke)
    }

    /// The stroke as Vision's scribble seed: one byte a pixel, 255 under the stroke and 0 elsewhere, from the top left
    /// (measured: a stroke flipped upside down outlines nothing), at half the frame's size (Vision scales it).
    static func scribble(_ stroke: [LookMasks.Point], width: Int, height: Int) -> CVPixelBuffer? {
        let w = max(2, width / 2), h = max(2, height / 2)
        var buf: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_OneComponent8, [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary, &buf) == kCVReturnSuccess,
              let buf else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let base = CVPixelBufferGetBaseAddress(buf),
              let cg = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        cg.setFillColor(gray: 0, alpha: 1); cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // A bitmap's first row is its top; its drawing space runs up from the bottom.
        let pts = stroke.map { CGPoint(x: $0.x * Double(w), y: (1 - $0.y) * Double(h)) }
        cg.setStrokeColor(gray: 1, alpha: 1); cg.setLineWidth(max(1, SkimFollow.strokeWidth * Double(max(w, h))))
        cg.setLineCap(.round); cg.setLineJoin(.round)
        cg.addLines(between: pts); cg.strokePath()
        return buf
    }

    /// While following a shape outlined by clicks (SkimTracker): the thing in `box` (fractions from the top left) of
    /// `image`, prompted by the box alone, as one shape; nil before macOS 27 or when nothing is there. Blocks its
    /// thread (the track's own, in the background) for the request, about 150 ms.
    static func outlineSync(_ image: CGImage, box: LookMasks.Box) -> LookMasks.Found? {
        guard #available(macOS 27.0, *) else { return nil }
        let done = DispatchSemaphore(value: 0), held = Held(image)
        Task.detached(priority: .utility) {
            let r = GenerateIterativeSegmentationRequest(seedBox: NormalizedRect(x: box.x, y: 1 - box.y - box.h, width: box.w, height: box.h))
            r.qualityLevel = .balanced
            held.out = try? await Session.found(r, held.image)
            done.signal()
        }
        done.wait()
        return held.out
    }

    /// The frame handed to the request's task and its answer handed back (written once, read after the wait).
    private final class Held: @unchecked Sendable {
        let image: CGImage
        var out: LookMasks.Found?
        init(_ image: CGImage) { self.image = image }
    }

    @available(macOS 27.0, *)
    actor Session {
        static let shared = Session()

        private var key: String?
        private var image: CGImage?
        private var points: [SkimFollow.PromptPoint] = []
        private var stroke: [LookMasks.Point]?
        private var request: GenerateIterativeSegmentationRequest?
        private var used = Date.distantPast
        /// How long an outline is held with no click.
        static let idle: TimeInterval = 120

        func status() async -> String {
            let s = await Self.assets(GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5)))
            return s == "ready" ? "ready" : s.hasPrefix("notReady") || s.hasPrefix("downloading") ? "download" : "no"
        }

        /// The model's state as Vision names it (ready, notReady, downloading, …), its case name only.
        private static func assets(_ r: GenerateIterativeSegmentationRequest) async -> String {
            String(describing: await r.assetStatus).split(separator: "(").first.map(String.init) ?? ""
        }

        func outline(key k: String, frame: Any?, points p: [SkimFollow.PromptPoint], stroke st: [LookMasks.Point]? = nil) async -> LookMasks.Found? {
            if Date().timeIntervalSince(used) > Self.idle { drop() }
            used = Date()
            // The same frame, stroke and clicks so far and more: only the new clicks go to the request.
            if k == key, st == stroke, let request, let image, let added = SkimFollow.promptAdded(points, p, seeded: st != nil) {
                do {
                    for q in added { try q.include ? request.addIncludedPoint(Self.vision(q)) : request.addExcludedPoint(Self.vision(q)) }
                    points = p
                    return try await Self.found(request, image)
                } catch { drop(); return nil }
            }
            // Else start again from the stroke or the first click, on this frame.
            drop()
            guard let cg = SetsMasks.image(frame: frame) else { return nil }
            let r: GenerateIterativeSegmentationRequest, rest: ArraySlice<SkimFollow.PromptPoint>
            if let st {
                guard let buf = SkimPrompt.scribble(st, width: cg.width, height: cg.height) else { return nil }
                r = GenerateIterativeSegmentationRequest(seedScribbleBuffer: CVReadOnlyPixelBuffer(unsafeBuffer: buf)); rest = p[...]
            } else {
                guard let first = p.first else { return nil }
                r = GenerateIterativeSegmentationRequest(seedPoint: Self.vision(first)); rest = p.dropFirst()
            }
            r.qualityLevel = .balanced
            do {
                if await Self.assets(r) != "ready" { try await r.downloadAssets() }
                for q in rest { try q.include ? r.addIncludedPoint(Self.vision(q)) : r.addExcludedPoint(Self.vision(q)) }
                let f = try await Self.found(r, cg)
                key = k; image = cg; points = p; stroke = st; request = r
                return f
            } catch { return nil }
        }

        private func drop() { key = nil; image = nil; points = []; stroke = nil; request = nil }

        /// Vision's points are from the bottom left; the page's from the top left.
        private static func vision(_ q: SkimFollow.PromptPoint) -> NormalizedPoint { NormalizedPoint(x: q.x, y: 1 - q.y) }

        /// The request's mask on `image`, at the frame's size, its edge snapped to the frame's own edges, as one shape.
        static func found(_ r: GenerateIterativeSegmentationRequest, _ image: CGImage) async throws -> LookMasks.Found? {
            guard let obs = try await r.perform(on: image), var mask = SetsMasks.luminance(try obs.cgImage) else { return nil }
            let w = image.width, h = image.height
            if mask.width != w || mask.height != h { mask = LookMasks.resized(mask, width: w, height: h) }
            if let guide = SetsMasks.luminance(image) { mask = LookMasks.guided(mask, guide: guide, radius: max(2, max(w, h) / 128)) }
            guard let box = LookMasks.box(mask) else { return nil }
            return LookMasks.Found(id: "pick", kind: .object, score: 1, box: box, area: LookMasks.area(mask), outline: LookMasks.outline(mask))
        }
    }
}
