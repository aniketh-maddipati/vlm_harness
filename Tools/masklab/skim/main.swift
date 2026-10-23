import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

// The app's own track (Skim ▸ Viewer ▸ Follow through the clip, `SkimTracker` from Lumina/Sets, compiled in) run over
// a clip without the app, so the mask lab scores it next to the other trackers, and so the sure / shaky / lost strip
// can be checked against the truth: how well a frame the app calls "sure" really holds the shape.
//
//   masklab-skim <clip> --start N (--box x,y,w,h | --point x,y) [--frames N] --out DIR
//
// The same arguments and the same output as masklab-track: DIR/000123.png (8-bit, 255 = in, at SkimFollow's proxy
// size) and DIR/timing.json, which also has `sure` (frames per state), `sure_frames` (each written frame's state) and
// `cues_frames` (what each state was judged from, `SkimFollow.Cues`), for score.py and the calibration fit. The start frame is chosen as the page chooses it: the shape Vision finds there that the box or point
// picks, by its kind and box. Frame numbers count from the clip's first frame, as ffmpeg's `n` does.

/// A value handed back from a task to the waiting main thread (written once, read after the wait).
final class Holder<T>: @unchecked Sendable { var value: T? }

struct Usage: Error, CustomStringConvertible { var description: String }

func parse(_ a: [String]) throws -> (clip: String, start: Int, box: LookMasks.Box?, point: LookMasks.Point?, frames: Int?, out: String) {
    var clip: String?, start = 0, box: LookMasks.Box?, point: LookMasks.Point?, frames: Int?, out: String?
    var i = 0
    func next() throws -> String { i += 1; guard i < a.count else { throw Usage(description: "\(a[i - 1]) needs a value") }; return a[i] }
    func nums(_ s: String, _ n: Int) throws -> [Double] {
        let v = s.split(separator: ",").compactMap { Double($0) }
        guard v.count == n, v.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else { throw Usage(description: "want \(n) numbers 0…1, got \(s)") }
        return v
    }
    while i < a.count {
        switch a[i] {
        case "--start": guard let v = Int(try next()), v >= 0 else { throw Usage(description: "--start wants a frame number") }; start = v
        case "--frames": guard let v = Int(try next()), v > 0 else { throw Usage(description: "--frames wants a count") }; frames = v
        case "--box": let v = try nums(try next(), 4); box = LookMasks.Box(x: v[0], y: v[1], w: v[2], h: v[3])
        case "--point": let v = try nums(try next(), 2); point = LookMasks.Point(x: v[0], y: v[1])
        case "--out": out = try next()
        case "--tracker", "--proxy", "--model", "--save-frames": _ = try next()     // masklab-track's, not used here
        default:
            guard clip == nil, !a[i].hasPrefix("--") else { throw Usage(description: "unknown argument \(a[i])") }
            clip = a[i]
        }
        i += 1
    }
    guard let clip, let out, box != nil || point != nil else {
        throw Usage(description: "usage: masklab-skim <clip> --start N (--box x,y,w,h | --point x,y) [--frames N] --out DIR")
    }
    return (clip, start, box, point, frames, out)
}

/// Every frame's presentation time, in order, from the compressed samples (nothing decoded).
func times(_ asset: AVAsset, _ track: AVAssetTrack) throws -> [Double] {
    let r = try AVAssetReader(asset: asset)
    let o = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    r.add(o)
    guard r.startReading() else { throw Usage(description: "can't read the clip") }
    var t: [Double] = []
    while let s = o.copyNextSampleBuffer() {
        if CMSampleBufferGetNumSamples(s) > 0 { t.append(CMSampleBufferGetPresentationTimeStamp(s).seconds) }
    }
    return t.filter(\.isFinite).sorted()
}

/// The frame at `t` seconds, decoded at `size`, as the tracker decodes it.
func frame(_ asset: AVAsset, _ track: AVAssetTrack, at t: Double, size: (width: Int, height: Int)) throws -> CGImage {
    let r = try AVAssetReader(asset: asset)
    let o = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
    ])
    r.add(o)
    r.timeRange = CMTimeRange(start: CMTime(seconds: t, preferredTimescale: 600_000), duration: CMTime(seconds: 1, preferredTimescale: 600))
    guard r.startReading() else { throw Usage(description: "can't read the clip") }
    defer { r.cancelReading() }
    while let s = o.copyNextSampleBuffer() {
        guard CMSampleBufferGetPresentationTimeStamp(s).seconds >= t - 1e-4, let b = CMSampleBufferGetImageBuffer(s) else { continue }
        var img: CGImage?
        VTCreateCGImageFromCVPixelBuffer(b, options: nil, imageOut: &img)
        if let img { return img }
    }
    throw Usage(description: "no frame at \(t) s")
}

func iou(_ a: LookMasks.Box, _ b: LookMasks.Box) -> Double {
    let w = max(0, min(a.x + a.w, b.x + b.w) - max(a.x, b.x)), h = max(0, min(a.y + a.h, b.y + b.h) - max(a.y, b.y))
    let i = w * h, u = a.w * a.h + b.w * b.h - i
    return u > 0 ? i / u : 0
}

func png(_ p: LookMasks.Plane, to url: URL) throws {
    let px = p.values.map { $0 >= 0.5 ? UInt8(255) : 0 }
    guard let prov = CGDataProvider(data: Data(px) as CFData),
          let img = CGImage(width: p.width, height: p.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: p.width,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                            provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw Usage(description: "can't write \(url.path)") }
    CGImageDestinationAddImage(d, img, nil)
    guard CGImageDestinationFinalize(d) else { throw Usage(description: "can't write \(url.path)") }
}

func main() throws {
    let o = try parse(Array(CommandLine.arguments.dropFirst()))
    let url = URL(fileURLWithPath: o.clip), out = URL(fileURLWithPath: o.out, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let asset = AVURLAsset(url: url)
    let sem = DispatchSemaphore(value: 0)
    let loaded = Holder<(AVAssetTrack, CGSize)>()
    Task.detached {
        if let t = try? await asset.loadTracks(withMediaType: .video).first, let s = try? await t.load(.naturalSize) { loaded.value = (t, s) }
        sem.signal()
    }
    sem.wait()
    guard let (track, natural) = loaded.value,
          let size = SkimFollow.proxySize(width: Int(natural.width.rounded()), height: Int(natural.height.rounded()))
    else { throw Usage(description: "\(url.lastPathComponent): no picture") }

    let pts = try times(asset, track)
    guard o.start < pts.count else { throw Usage(description: "\(url.lastPathComponent) has \(pts.count) frames; --start \(o.start) is past its end") }
    let last = min(pts.count, o.start + (o.frames ?? pts.count)) - 1
    let t0 = pts[o.start]

    // The shape chosen on the start frame, as a click or a box on the page chooses it.
    let first = try frame(asset, track, at: t0, size: size)
    let found = (SetsMasks.masks(first) ?? []).filter { SkimFollow.boxed($0.kind) }
    let pick: LookMasks.Found?
    if let p = o.point {
        let under = found.filter { $0.box.x <= p.x && p.x <= $0.box.x + $0.box.w && $0.box.y <= p.y && p.y <= $0.box.y + $0.box.h }
        pick = under.min { $0.area < $1.area }
    } else {
        pick = found.map { ($0, iou($0.box, o.box!)) }.filter { $0.1 >= 0.05 }.max { $0.1 < $1.1 }?.0
    }
    let kind = pick?.kind ?? .object, box = pick?.box ?? o.box ?? LookMasks.Box(x: o.point!.x - 0.05, y: o.point!.y - 0.05, w: 0.1, h: 0.1)

    let started = Date()
    let id = "masklab"
    SkimTracker.logsLook = true
    SkimTracker.shared.start(id: id, url: url, kind: kind, box: box, t0: t0)
    var state = "run", why = "", got: [SkimFollow.Tracked] = []
    while true {
        guard let p = SkimTracker.shared.poll(id, from: Int.max) else { throw Usage(description: "the track went away") }
        state = p["state"] as? String ?? "failed"; why = p["why"] as? String ?? ""
        got = SkimTracker.shared.tracked(id) ?? []
        // Forward frames come first: once the last one asked for is in, the rest is not needed.
        if o.start == 0 || o.frames != nil, let t = got.last?.t, t >= pts[last] - 1e-4 { break }
        if state != "run" { break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    SkimTracker.shared.end(id)
    let totalMs = Date().timeIntervalSince(started) * 1000
    guard state != "failed" else { throw Usage(description: "\(url.lastPathComponent): the track failed: \(why)") }

    // Each followed frame to its frame number by its time, then a mask per frame from start to last.
    var byFrame: [Int: SkimFollow.Tracked] = [:]
    for f in got {
        var lo = 0, hi = pts.count - 1
        while lo < hi { let m = (lo + hi) / 2; if pts[m] < f.t - 1e-4 { lo = m + 1 } else { hi = m } }
        let n = lo > 0 && abs(pts[lo - 1] - f.t) < abs(pts[lo] - f.t) ? lo - 1 : lo
        if n >= o.start && n <= last { byFrame[n] = f }
    }
    var counts = ["sure": 0, "shaky": 0, "lost": 0, "missing": 0], states: [String] = [], lost: [Int] = [], cues: [Any] = []
    for n in o.start...last {
        let f = byFrame[n]
        let s = f?.sure.rawValue ?? "missing"
        counts[s, default: 0] += 1; states.append(s)
        cues.append(f?.cues?.json ?? NSNull())
        let outline = f?.step.shape?.outline ?? []
        let plane = LookMasks.raster(outline, width: size.width, height: size.height)
        if outline.isEmpty { lost.append(n) }
        try png(plane, to: out.appendingPathComponent(String(format: "%06d.png", n)))
    }

    let frames = last - o.start + 1
    var len = 0
    sysctlbyname("hw.model", nil, &len, nil, 0)
    var model = [CChar](repeating: 0, count: max(1, len))
    sysctlbyname("hw.model", &model, &len, nil, 0)
    let machine = String(cString: model)
    let timing: [String: Any] = [
        "tracker": "skim", "clip": url.deletingPathExtension().lastPathComponent, "start_frame": o.start, "frames": frames,
        "total_ms": totalMs, "per_frame_ms": [Double](), "lost": lost, "proxy": [size.width, size.height],
        "source": [Int(natural.width), Int(natural.height)], "chosen": ["kind": kind.rawValue, "picked": pick != nil],
        "sure": counts, "sure_frames": states, "cues_frames": cues, "refind": SkimFollow.refind,
        "device": ["model": machine, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                   "cores": ProcessInfo.processInfo.activeProcessorCount,
                   "memory_gb": Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824],
    ]
    try JSONSerialization.data(withJSONObject: timing, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("timing.json"))
    print(String(format: "skim %@: %d frames, %.1f fps, sure %d / shaky %d / lost %d%@", url.deletingPathExtension().lastPathComponent,
                 frames, Double(frames) / max(totalMs / 1000, 1e-6), counts["sure"]!, counts["shaky"]!, counts["lost"]! + counts["missing"]!,
                 pick == nil ? " (no shape under the prompt: started from the box as an object)" : ""))
}

do { try main() } catch {
    FileHandle.standardError.write(Data("masklab-skim: \(error)\n".utf8))
    exit(2)
}
