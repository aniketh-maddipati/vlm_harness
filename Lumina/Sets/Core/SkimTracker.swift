import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import Vision
import VideoToolbox

/// Skim's `lumina.video.track`: one chosen shape followed through every frame of a clip, read by the Mac itself
/// (AVAssetReader at `SkimFollow.proxyEdge`), in the background. The page's Follow sent eight JPEGs a second from its own
/// `<video>`; this reads every frame at a proxy with no round trip, so the matte is made from the outline of each frame
/// and never mixes two (`SkimFollow.matteFrame`).
///
/// From the frame the shape was chosen on, forward to the end, then back to the start (read in one-second stretches,
/// since a reader only goes forward). Each frame goes through a `SkimFollower.Trail` (Vision's tracker, put back on the
/// shape Vision finds there). When the shape is lost for `SkimFollow.lostFor` frames, the shapes in each frame are
/// compared with the chosen one by Vision's feature print (`SkimFollow.refound`), so a person who walks behind a pillar
/// is found again. Each frame says how sure it is (`SkimFollow.sureness`), for the strip under the scrub bar.
///
/// Nothing is written: the followed frames are held in memory for the page to fetch (`poll`) and for the matte
/// (`samples`), until the page ends the track, a newer one takes the place of the oldest, or `SkimFollow.kept` passes.
/// The clip's preferred transform is not applied (camera clips are landscape; the mask lab does the same).
nonisolated final class SkimTracker: @unchecked Sendable {
    static let shared = SkimTracker()

    private final class Job {
        let id: String
        /// A fix: the track whose stretch `span` this one re-tracks, and takes the place of when it is done.
        var into: String?
        var span: (from: Double, to: Double)?
        var state = "run"          // run, done, stopped, failed
        var why = ""
        var frames: [SkimFollow.Tracked] = []
        var expected = 0
        var stop = false
        var touched = Date()
        init(id: String) { self.id = id }
    }

    private let lock = NSLock()
    private var jobs: [String: Job] = [:]

    /// Starts following `kind` chosen at `box` (fractions from the top left) on the frame at `t0` seconds of the clip
    /// at `url`; any track by that id is stopped and let go first. With `fix`, only the stretch `from … to` is followed
    /// and, once done, takes the place of that stretch in the track `into` (a fix counts against no limit and goes with
    /// its track).
    func start(id: String, url: URL, kind: LookMasks.Kind, box: LookMasks.Box, t0: Double, fix: (into: String, from: Double, to: Double)? = nil) {
        let job = Job(id: id)
        job.into = fix?.into
        job.span = fix.map { (max(0, $0.from), max($0.from, $0.to)) }
        lock.withLock {
            let now = Date()
            for (k, j) in jobs where now.timeIntervalSince(j.touched) >= SkimFollow.kept { letGo(k) }
            letGo(id)
            while jobs.values.filter({ $0.into == nil }).count >= SkimFollow.tracks, job.into == nil,
                  let oldest = jobs.values.filter({ $0.into == nil }).min(by: { $0.touched < $1.touched })?.id { letGo(oldest) }
            jobs[id] = job
        }
        Task.detached(priority: .utility) { [self] in
            do { try await run(job, url: url, kind: kind, box: box, t0: t0) } catch {
                lock.withLock { if job.state == "run" { job.state = "failed"; job.why = (error as? Failed)?.why ?? "the clip couldn’t be read" } }
            }
            lock.withLock {
                if job.state == "run" { job.state = job.stop ? "stopped" : "done" }
                // a fix that finished takes the place of its stretch in its track
                if job.state == "done", let into = job.into, let span = job.span, let base = jobs[into], base.state == "done" || base.state == "stopped" {
                    base.frames = SkimFollow.merged(base.frames, patch: job.frames, from: span.from, to: span.to)
                }
            }
        }
    }

    /// Under the lock: the track `id` and its fixes stopped and let go.
    private func letGo(_ id: String) {
        guard let j = jobs.removeValue(forKey: id) else { return }
        j.stop = true
        for (k, f) in jobs where f.into == id { f.stop = true; jobs.removeValue(forKey: k) }
    }

    func end(_ id: String) { lock.withLock { letGo(id) } }

    /// The track `id` for the page: its state, how far it is (0 … 1), why it failed, the followed frames from `from`
    /// (at most `SkimFollow.page`, in the order they were followed), how many there are, and the strip so far.
    /// Nil: no such track.
    func poll(_ id: String, from: Int) -> [String: Any]? {
        lock.withLock {
            guard let j = jobs[id] else { return nil }
            j.touched = Date()
            let n = j.frames.count, a = max(0, min(n, from)), b = min(n, a + SkimFollow.page)
            let done = j.state == "run" ? (j.expected > 0 ? min(0.99, Double(n) / Double(j.expected)) : 0) : 1
            var o: [String: Any] = ["state": j.state, "done": (done * 1000).rounded() / 1000, "n": n, "from": a,
                                    "frames": j.frames[a..<b].map(\.json)]
            if !j.why.isEmpty { o["why"] = j.why }
            if j.state != "run" || b == n { o["strip"] = SkimFollow.strip(j.frames.map { ($0.t, $0.sure) }).map(\.json) }
            return o
        }
    }

    /// Every followed frame of the track `id` so far, in the order followed, with its cues (the mask lab reads these to
    /// score the strip; the page polls instead). Nil: no such track.
    func tracked(_ id: String) -> [SkimFollow.Tracked]? { lock.withLock { jobs[id]?.frames } }

    /// The followed frames of a finished track, in time order, as the matte takes them. Nil while it runs, or when there
    /// is no such track.
    func samples(_ id: String) -> [SkimFollow.Sample]? {
        lock.withLock {
            guard let j = jobs[id], j.state == "done" || j.state == "stopped", !j.frames.isEmpty else { return nil }
            j.touched = Date()
            return j.frames.sorted { $0.t < $1.t }.map { SkimFollow.Sample(t: $0.t, outline: $0.step.shape?.outline ?? []) }
        }
    }

    // MARK: Following

    private struct Failed: Error { var why: String }

    private func stopped(_ j: Job) -> Bool { lock.withLock { j.stop } }
    private func add(_ f: SkimFollow.Tracked, to j: Job) -> Bool {
        lock.withLock {
            guard !j.stop, j.frames.count < SkimFollow.maxTracked else { return false }
            j.frames.append(f); return true
        }
    }

    /// What one direction of the track carries from frame to frame.
    private final class Way {
        let trail: SkimFollower.Trail
        var lost = 0, wasLost = false
        var area: Double?
        /// Frames looked at through the window since the last whole frame (`SkimFollow.fullEvery` forces a whole one),
        /// and whether the tracker wavered on the last frame (the next is looked at whole).
        var sinceFull = SkimFollow.fullEvery, wavered = false
        init(_ t: SkimFollower.Trail) { trail = t }
    }

    private func run(_ j: Job, url: URL, kind: LookMasks.Kind, box: LookMasks.Box, t0: Double) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failed(why: "the clip has no picture") }
        let natural = try await track.load(.naturalSize), length = try await asset.load(.duration).seconds
        let fps = Double(try await track.load(.nominalFrameRate))
        guard let size = SkimFollow.proxySize(width: Int(natural.width.rounded()), height: Int(natural.height.rounded())), length.isFinite, length > 0 else {
            throw Failed(why: "the clip couldn’t be read")
        }
        let span = j.span.map { (from: min($0.from, length), to: min($0.to, length)) } ?? (from: 0, to: length)
        lock.withLock { j.expected = Int(((span.to - span.from) * (fps > 0 ? fps : 30)).rounded()) }
        let start = min(max(span.from, t0), max(span.from, span.to - 0.001))

        // The chosen shape's feature print, from the first frame read, to find it again after it is lost.
        var print: VNFeaturePrintObservation?
        var startBox = box

        // Forward from the frame it was chosen on.
        let fwd = Way(SkimFollower.Trail(kind: kind, box: box))
        var first = true
        try read(track: track, asset: asset, size: size, from: start, to: span.to) { t, image in
            if self.stopped(j) { return false }
            let found = self.shapes(fwd, image)
            let f = self.follow(fwd, image: image, t: t, found: found, first: first, print: print)
            if first {
                if let s = f.step.shape { startBox = s.box }
                if SkimFollow.boxed(kind) { print = Self.featurePrint(image, box: f.step.shape?.box ?? box) }
                first = false
            }
            return self.add(f, to: j)
        }
        guard !stopped(j) else { return }

        // Back to the start, a second at a time, each stretch from its end to its start.
        let back = Way(SkimFollower.Trail(kind: kind, box: startBox))
        for c0 in SkimFollow.backChunks(from: start, chunk: 1) where c0.to > span.from {
            let c = (from: max(c0.from, span.from), to: c0.to)
            var frames: [(t: Double, image: CGImage)] = []
            try read(track: track, asset: asset, size: size, from: c.from, to: c.to) { t, image in
                guard t < c.to - 1e-4, let copy = Self.copied(image) else { return !self.stopped(j) }
                frames.append((t, copy)); return !self.stopped(j)
            }
            for (t, image) in frames.reversed() {
                guard !stopped(j) else { return }
                let found = shapes(back, image)
                guard add(follow(back, image: image, t: t, found: found, first: false, print: print), to: j) else { return }
            }
        }
    }

    /// The shapes in a frame for one direction of the track: through the window around the followed box
    /// (`SkimFollow.window`, `SetsMasks.near`), or the whole frame on the first frame, every `SkimFollow.fullEvery`
    /// frames, while the shape is lost, after the tracker wavered, for the sky and the background, and when the shape
    /// runs into the window's edge.
    private func shapes(_ w: Way, _ image: CGImage) -> [LookMasks.Found] {
        if SkimFollow.boxed(w.trail.kind), w.lost == 0, !w.wavered, w.sinceFull < SkimFollow.fullEvery,
           let box = w.trail.box, let window = SkimFollow.window(around: box),
           let near = SetsMasks.near(image, window: window) {
            let m = SkimFollow.match(kind: w.trail.kind, box: box, in: near)
            if let m, !SkimFollow.cut(m.box, by: window) { w.sinceFull += 1; return near }
        }
        w.sinceFull = 0
        return SetsMasks.masks(image) ?? []
    }

    /// One frame of one direction: the trail's step, the shape found again by its feature print when it has been lost
    /// a while, and how sure the frame is.
    private func follow(_ w: Way, image: CGImage, t: Double, found: [LookMasks.Found], first: Bool, print: VNFeaturePrintObservation?) -> SkimFollow.Tracked {
        var (step, figure, agree, rivals) = w.trail.step(image, found: found, first: first)
        var refound = false
        if step.shape == nil, SkimFollow.boxed(w.trail.kind) {
            w.lost += 1
            if w.lost >= SkimFollow.lostFor, let print {
                let c = found.filter { SkimFollow.refindable(w.trail.kind, as: $0.kind) }.compactMap { s -> (id: String, kind: LookMasks.Kind, distance: Double)? in
                    guard let p = Self.featurePrint(image, box: s.box) else { return nil }
                    var d: Float = 0
                    guard (try? p.computeDistance(&d, to: print)) != nil else { return nil }
                    return (s.id, s.kind, Double(d))
                }
                if let id = SkimFollow.refound(w.trail.kind, among: c), let s = found.first(where: { $0.id == id }) {
                    w.trail.place(s)
                    step = SkimFollow.Step(box: s.box, held: true, shape: s)
                    refound = true; figure = nil; agree = nil
                }
            }
        }
        if step.shape != nil { refound = refound || w.wasLost; w.lost = 0 }
        let sure = SkimFollow.sureness(tracker: figure, found: step.shape != nil, area: step.shape?.area, last: w.area, refound: refound)
        let cues = SkimFollow.Cues(tracker: figure, agree: agree, area: step.shape?.area, last: w.area, refound: refound,
                                   score: step.shape?.score, rivals: rivals, lost: w.lost)
        w.wasLost = step.shape == nil
        w.wavered = (figure ?? 1) < SkimFollow.steady
        if let a = step.shape?.area { w.area = a }
        return SkimFollow.Tracked(t: t, step: step, sure: sure, cues: cues)
    }

    /// Reads the clip's frames from `from` to `to` seconds at `size`, each handed to `each` with its time; `each`
    /// answers false to stop.
    private func read(track: AVAssetTrack, asset: AVAsset, size: (width: Int, height: Int), from: Double, to: Double,
                      each: (Double, CGImage) throws -> Bool) throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failed(why: "the clip’s picture couldn’t be decoded") }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600_000), end: CMTime(seconds: to, preferredTimescale: 600_000))
        guard reader.startReading() else { throw Failed(why: "the clip couldn’t be read") }
        defer { reader.cancelReading() }
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard t.isFinite, t >= from - 1e-4 else { continue }
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
            guard let image else { continue }
            if try !each(t, image) { return }
        }
        if reader.status == .failed { throw Failed(why: "the clip couldn’t be decoded") }
    }

    /// A frame's own copy of its pixels (a decoded frame shares the reader's buffers, which it reuses).
    private static func copied(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// Vision's feature print of what is in `box` (fractions from the top left) of `image`.
    private static func featurePrint(_ image: CGImage, box: LookMasks.Box) -> VNFeaturePrintObservation? {
        let r = SkimFollower.rect(SkimFollow.flipped(box)).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard r.width > 0.01, r.height > 0.01 else { return nil }
        let req = VNGenerateImageFeaturePrintRequest()
        req.regionOfInterest = r
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([req])) != nil else { return nil }
        return req.results?.first
    }
}
