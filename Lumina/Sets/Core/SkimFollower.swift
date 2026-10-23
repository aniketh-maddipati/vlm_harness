import CoreGraphics
import Foundation
import Vision

/// Skim's `lumina.video.follow`: one chosen shape followed through a clip, frame by frame, as the page sends the
/// frames it draws from its own `<video>` (Skim ▸ Viewer ▸ Follow). A person or an object is followed by its box with
/// Vision's object tracker (`VNTrackObjectRequest`, the mask lab's `vision-box`); in each frame the shapes are found as
/// `skimMasks` finds them, and the one that overlaps the box is the shape there (`SkimFollow.match`), which also puts
/// the box back on it, so the box does not drift off the thing it follows. The sky and the background are found again
/// in each frame. Nothing leaves the Mac and nothing is kept: a follow is the tracker's last box, in memory, until the
/// page ends it, a newer follow takes its place, or it is left idle (`SkimFollow.open`, `SkimFollow.idle`).
///
/// Thread-safe. One frame at a time across all follows (each frame runs Vision's finders, which use the Neural Engine).
nonisolated final class SkimFollower: @unchecked Sendable {
    static let shared = SkimFollower()

    private final class Follow {
        let trail: Trail
        var used = Date()
        init(_ trail: Trail) { self.trail = trail }
    }

    /// One shape followed frame by frame: Vision's tracker on its box, put back each frame on the shape Vision finds
    /// there (`SkimFollow.match`), so the box does not drift off the thing it follows. The page's Follow (`step`) and
    /// the Mac's own track (`SkimTracker`) both go frame by frame through one of these. Not thread-safe: one caller.
    nonisolated final class Trail {
        let kind: LookMasks.Kind
        private var handler = VNSequenceRequestHandler()
        private var last: VNDetectedObjectObservation?
        private(set) var box: LookMasks.Box?

        /// A trail of the shape of `kind` chosen at `box` (fractions from the top left) in the frame it starts on.
        init(kind: LookMasks.Kind, box: LookMasks.Box) {
            self.kind = kind
            if SkimFollow.boxed(kind) { self.box = box; last = VNDetectedObjectObservation(boundingBox: SkimFollower.rect(SkimFollow.flipped(box))) }
        }

        /// The next frame and the shapes Vision found in it. `first`: the frame the trail starts on (the box is not
        /// tracked into it). The tracker's own figure comes back with the step (nil for the sky and the background, and
        /// on the first frame).
        func step(_ image: CGImage, found: [LookMasks.Found], first: Bool) -> (step: SkimFollow.Step, tracker: Double?) {
            guard SkimFollow.boxed(kind) else {
                let s = SkimFollow.match(kind: kind, box: nil, in: found)
                return (SkimFollow.Step(box: s?.box, held: s != nil, shape: s), nil)
            }
            var tracked = first, figure: Double?
            if !first, let last {
                let req = VNTrackObjectRequest(detectedObjectObservation: last)
                req.trackingLevel = .accurate
                if (try? handler.perform([req], on: image)) != nil, let o = req.results?.first as? VNDetectedObjectObservation {
                    self.last = o
                    figure = Double(o.confidence)
                    if Double(o.confidence) >= SkimFollow.hold { tracked = true; box = SkimFollow.flipped(SkimFollower.box(o.boundingBox)) }
                }
            }
            // The shape on the box puts the box back on the shape: a new start for the tracker, from what Vision found.
            let s = SkimFollow.match(kind: kind, box: box, in: found)
            if let s { place(s) }
            return (SkimFollow.Step(box: box, held: tracked || s != nil, shape: s), figure)
        }

        /// The tracker started again on `shape` (the shape on the box, or one found again after it was lost). A fresh
        /// handler with it: each observation handed to the tracker is a tracker of its own, and Vision allows only a few
        /// at once; the old handler takes its tracker with it.
        func place(_ shape: LookMasks.Found) {
            box = shape.box
            last = VNDetectedObjectObservation(boundingBox: SkimFollower.rect(SkimFollow.flipped(shape.box)))
            handler = VNSequenceRequestHandler()
        }
    }

    private let lock = NSLock()
    private var follows: [String: Follow] = [:]

    var count: Int { lock.withLock { follows.count } }

    func end(_ id: String) { lock.withLock { _ = follows.removeValue(forKey: id) } }

    /// One frame of the follow `id`: with `start`, a new follow of that shape from this frame (any follow by that id is
    /// let go first); without, the next frame of one already started. Nil when the frame is not a JPEG, or there is no
    /// such follow.
    func step(id: String, frame: Any?, start: (kind: LookMasks.Kind, box: LookMasks.Box)?) -> SkimFollow.Step? {
        guard let image = SetsMasks.image(frame: frame) else { return nil }
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        follows = follows.filter { now.timeIntervalSince($0.value.used) < SkimFollow.idle }
        let f: Follow
        if let start {
            follows.removeValue(forKey: id)
            while follows.count >= SkimFollow.open, let oldest = follows.min(by: { $0.value.used < $1.value.used })?.key { follows.removeValue(forKey: oldest) }
            f = Follow(Trail(kind: start.kind, box: start.box))
            follows[id] = f
        } else {
            guard let had = follows[id] else { return nil }
            f = had
        }
        f.used = now
        return f.trail.step(image, found: SetsMasks.masks(image) ?? [], first: start != nil).step
    }

    static func rect(_ b: LookMasks.Box) -> CGRect { CGRect(x: b.x, y: b.y, width: b.w, height: b.h) }
    static func box(_ r: CGRect) -> LookMasks.Box {
        let x = min(1, max(0, Double(r.minX))), y = min(1, max(0, Double(r.minY)))
        return LookMasks.Box(x: x, y: y, w: min(1 - x, max(0, Double(r.width))), h: min(1 - y, max(0, Double(r.height))))
    }
}
