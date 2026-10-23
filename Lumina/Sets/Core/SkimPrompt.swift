import CoreGraphics
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
    /// model can't run. `key` names the frame: clicks on the same key add to the outline already made.
    static func outline(key: String, frame: Any?, points: [SkimFollow.PromptPoint]) async -> LookMasks.Found? {
        guard #available(macOS 27.0, *) else { return nil }
        return await Session.shared.outline(key: key, frame: frame, points: points)
    }

    @available(macOS 27.0, *)
    actor Session {
        static let shared = Session()

        private var key: String?
        private var image: CGImage?
        private var points: [SkimFollow.PromptPoint] = []
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

        func outline(key k: String, frame: Any?, points p: [SkimFollow.PromptPoint]) async -> LookMasks.Found? {
            if Date().timeIntervalSince(used) > Self.idle { drop() }
            used = Date()
            // The same frame and the clicks so far and more: only the new clicks go to the request.
            if k == key, let request, let image, let added = SkimFollow.promptAdded(points, p) {
                do {
                    for q in added { try q.include ? request.addIncludedPoint(Self.vision(q)) : request.addExcludedPoint(Self.vision(q)) }
                    points = p
                    return try await Self.found(request, image)
                } catch { drop(); return nil }
            }
            // Else start again from the first click, on this frame.
            drop()
            guard let first = p.first, let cg = SetsMasks.image(frame: frame) else { return nil }
            let r = GenerateIterativeSegmentationRequest(seedPoint: Self.vision(first))
            r.qualityLevel = .balanced
            do {
                if await Self.assets(r) != "ready" { try await r.downloadAssets() }
                for q in p.dropFirst() { try q.include ? r.addIncludedPoint(Self.vision(q)) : r.addExcludedPoint(Self.vision(q)) }
                let f = try await Self.found(r, cg)
                key = k; image = cg; points = p; request = r
                return f
            } catch { return nil }
        }

        private func drop() { key = nil; image = nil; points = []; request = nil }

        /// Vision's points are from the bottom left; the page's from the top left.
        private static func vision(_ q: SkimFollow.PromptPoint) -> NormalizedPoint { NormalizedPoint(x: q.x, y: 1 - q.y) }

        /// The request's mask on `image`, at the frame's size, its edge snapped to the frame's own edges, as one shape.
        private static func found(_ r: GenerateIterativeSegmentationRequest, _ image: CGImage) async throws -> LookMasks.Found? {
            guard let obs = try await r.perform(on: image), var mask = SetsMasks.luminance(try obs.cgImage) else { return nil }
            let w = image.width, h = image.height
            if mask.width != w || mask.height != h { mask = LookMasks.resized(mask, width: w, height: h) }
            if let guide = SetsMasks.luminance(image) { mask = LookMasks.guided(mask, guide: guide, radius: max(2, max(w, h) / 128)) }
            guard let box = LookMasks.box(mask) else { return nil }
            return LookMasks.Found(id: "pick", kind: .object, score: 1, box: box, area: LookMasks.area(mask), outline: LookMasks.outline(mask))
        }
    }
}
