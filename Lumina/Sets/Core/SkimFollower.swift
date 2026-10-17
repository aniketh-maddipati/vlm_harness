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
        let kind: LookMasks.Kind
        var handler = VNSequenceRequestHandler()
        var last: VNDetectedObjectObservation?
        var box: LookMasks.Box?
        var used = Date()
        init(kind: LookMasks.Kind) { self.kind = kind }
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
            f = Follow(kind: start.kind)
            if SkimFollow.boxed(start.kind) { f.box = start.box; f.last = VNDetectedObjectObservation(boundingBox: Self.rect(SkimFollow.flipped(start.box))) }
            follows[id] = f
        } else {
            guard let had = follows[id] else { return nil }
            f = had
        }
        f.used = now
        let found = SetsMasks.masks(image) ?? []
        guard SkimFollow.boxed(f.kind) else {
            let s = SkimFollow.match(kind: f.kind, box: nil, in: found)
            return SkimFollow.Step(box: s?.box, held: s != nil, shape: s)
        }
        var tracked = start != nil
        if start == nil, let last = f.last {
            let req = VNTrackObjectRequest(detectedObjectObservation: last)
            req.trackingLevel = .accurate
            if (try? f.handler.perform([req], on: image)) != nil, let o = req.results?.first as? VNDetectedObjectObservation {
                f.last = o
                if Double(o.confidence) >= SkimFollow.hold { tracked = true; f.box = SkimFollow.flipped(Self.box(o.boundingBox)) }
            }
        }
        // The shape on the box puts the box back on the shape: a new start for the tracker, from what Vision found.
        let s = SkimFollow.match(kind: f.kind, box: f.box, in: found)
        // A fresh handler with it: each observation handed to the tracker is a tracker of its own, and Vision allows only
        // a few at once; the old handler takes its tracker with it.
        if let s {
            f.box = s.box
            f.last = VNDetectedObjectObservation(boundingBox: Self.rect(SkimFollow.flipped(s.box)))
            f.handler = VNSequenceRequestHandler()
        }
        return SkimFollow.Step(box: f.box, held: tracked || s != nil, shape: s)
    }

    private static func rect(_ b: LookMasks.Box) -> CGRect { CGRect(x: b.x, y: b.y, width: b.w, height: b.h) }
    private static func box(_ r: CGRect) -> LookMasks.Box {
        let x = min(1, max(0, Double(r.minX))), y = min(1, max(0, Double(r.minY)))
        return LookMasks.Box(x: x, y: y, w: min(1 - x, max(0, Double(r.width))), h: min(1 - y, max(0, Double(r.height))))
    }
}
