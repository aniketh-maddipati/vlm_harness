import Foundation

// The Foundation-only half of masklab-track: arguments, boxes, masks, how a tracker picks one
// foreground instance, and the timing file. Builds and is tested on Linux
// (`swift test --package-path Tools/masklab/track`); the Mac half (AVFoundation, Vision, Core ML)
// only feeds it pixel buffers turned into `Mask` / `LabelMap`.
//
// Coordinates: a Box or Point is normalized to the frame (0…1), origin top left, the way the
// prompts file and the PNG masks read. Vision's rects are origin bottom left; `flippedY` converts
// both ways.

public enum Tracker: String, CaseIterable, Sendable {
    case visionBox = "vision-box"
    case visionInstance = "vision-instance"
    case sam2 = "sam2-coreml"
    /// Not a tracker: on each frame the foreground instance that best matches the hand label. The most any tracker
    /// that picks one of Vision's instances could score, so a low number here is the masks, not the tracking.
    case visionOracle = "vision-oracle"
}

public struct Point: Equatable, Codable, Sendable {
    public var x: Double, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Box: Equatable, Codable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }

    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var area: Double { max(0, w) * max(0, h) }
    public var centre: Point { Point(x: x + w / 2, y: y + h / 2) }

    public func intersection(_ o: Box) -> Double {
        max(0, min(maxX, o.maxX) - max(x, o.x)) * max(0, min(maxY, o.maxY) - max(y, o.y))
    }

    public func iou(_ o: Box) -> Double {
        let i = intersection(o), u = area + o.area - i
        return u > 0 ? i / u : 0
    }

    /// The same box with its origin at the other vertical edge (top left ⇄ Vision's bottom left).
    public var flippedY: Box { Box(x: x, y: 1 - y - h, w: w, h: h) }

    /// Inside the frame, never narrower than `minSide` (Vision refuses an empty box).
    public func clamped(minSide: Double = 0.002) -> Box {
        let x0 = min(max(x, 0), 1 - minSide), y0 = min(max(y, 0), 1 - minSide)
        let x1 = max(min(maxX, 1), x0 + minSide), y1 = max(min(maxY, 1), y0 + minSide)
        return Box(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }
}

public enum Prompt: Equatable, Sendable {
    case box(Box)
    case point(Point)
}

// ——— arguments

public struct UsageError: Error, CustomStringConvertible {
    public let description: String
    public init(_ d: String) { description = d }
}

public struct Options: Equatable, Sendable {
    public var clip: String
    public var start = 0
    public var prompt: Prompt
    public var proxy = 720
    public var tracker: Tracker
    public var model: String?
    public var out: String
    /// Stop after this many frames from `start` (nil: to the end of the clip).
    public var maxFrames: Int?
    /// Also write every Nth proxy frame as a PNG under `out/frames/`, to label on.
    public var saveFramesEvery: Int?
    /// vision-oracle: the clip's labels folder (`<frame>.png`).
    public var labels: String?

    public static let usage = """
    masklab-track: one mask tracker on one clip (Tools/masklab/README.md)

      masklab-track <clip> --start <frame> (--box x,y,w,h | --point x,y) --tracker <name> --out <dir>
                    [--proxy 720] [--model <dir>] [--labels <dir>] [--frames <n>] [--save-frames <n>]

      --box / --point   the prompt on the start frame, normalized 0…1, origin top left
      --tracker         vision-box | vision-instance | sam2-coreml (experimental, needs --model)
                        | vision-oracle (the best instance per labelled frame, needs --labels)
      --labels          the clip's labels folder (<frame>.png), for vision-oracle
      --proxy           long edge the frames are decoded at (AVAssetReader scales); never upscales
      --frames          stop after this many frames (default: to the end)
      --save-frames     also write every Nth proxy frame to <out>/frames/ (for labelling)

    Writes <out>/<frame>.png (8-bit, 255 = in, frame numbers count from the clip's first frame)
    and <out>/timing.json.
    """

    public static func parse(_ argv: [String]) throws -> Options {
        var clip: String?, start = 0, prompt: Prompt?, proxy = 720, tracker: Tracker?, model: String?, out: String?
        var maxFrames: Int?, saveEvery: Int?, labels: String?
        var i = 0
        func value(_ name: String) throws -> String {
            guard i + 1 < argv.count else { throw UsageError("\(name) needs a value") }
            i += 1
            return argv[i]
        }
        func int(_ name: String, _ s: String, min lo: Int) throws -> Int {
            guard let v = Int(s), v >= lo else { throw UsageError("\(name): expected a whole number ≥ \(lo), got \(s)") }
            return v
        }
        func numbers(_ name: String, _ s: String, count: Int) throws -> [Double] {
            let v = s.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard v.count == count, v.allSatisfy({ $0 != nil && $0! >= 0 && $0! <= 1 }) else {
                throw UsageError("\(name): expected \(count) numbers between 0 and 1 separated by commas, got \(s)")
            }
            return v.map { $0! }
        }
        while i < argv.count {
            let a = argv[i]
            switch a {
            case "--start": start = try int(a, try value(a), min: 0)
            case "--box":
                let v = try numbers(a, try value(a), count: 4)
                guard v[2] > 0, v[3] > 0, v[0] + v[2] <= 1.0001, v[1] + v[3] <= 1.0001 else {
                    throw UsageError("--box: x,y,w,h must have w, h > 0 and stay inside the frame")
                }
                prompt = .box(Box(x: v[0], y: v[1], w: v[2], h: v[3]))
            case "--point":
                let v = try numbers(a, try value(a), count: 2)
                prompt = .point(Point(x: v[0], y: v[1]))
            case "--proxy": proxy = try int(a, try value(a), min: 64)
            case "--tracker":
                let s = try value(a)
                guard let t = Tracker(rawValue: s) else {
                    throw UsageError("--tracker: one of \(Tracker.allCases.map(\.rawValue).joined(separator: ", ")), got \(s)")
                }
                tracker = t
            case "--model": model = try value(a)
            case "--labels": labels = try value(a)
            case "--out": out = try value(a)
            case "--frames": maxFrames = try int(a, try value(a), min: 1)
            case "--save-frames": saveEvery = try int(a, try value(a), min: 1)
            case "-h", "--help": throw UsageError(usage)
            default:
                if a.hasPrefix("-") { throw UsageError("unknown option \(a)") }
                guard clip == nil else { throw UsageError("one clip only, got \(clip!) and \(a)") }
                clip = a
            }
            i += 1
        }
        guard let clip else { throw UsageError("no clip given\n\n" + usage) }
        guard let prompt else { throw UsageError("give --box x,y,w,h or --point x,y") }
        guard let tracker else { throw UsageError("give --tracker") }
        guard let out else { throw UsageError("give --out <dir>") }
        if tracker == .sam2, model == nil {
            throw UsageError("sam2-coreml needs --model <dir>: a folder with the image encoder, prompt encoder and mask decoder .mlpackage / .mlmodelc (see Tools/masklab/README.md). Nothing is downloaded.")
        }
        if tracker == .visionOracle, labels == nil {
            throw UsageError("vision-oracle needs --labels <dir>: the clip's hand labels, one <frame>.png each")
        }
        return Options(clip: clip, start: start, prompt: prompt, proxy: proxy, tracker: tracker, model: model,
                       out: out, maxFrames: maxFrames, saveFramesEvery: saveEvery, labels: labels)
    }
}

/// The decode size for a source frame: the long edge at most `longEdge`, aspect kept, both sides
/// even (the decoder's scaler wants even sizes), never larger than the source.
public func proxySize(width: Int, height: Int, longEdge: Int) -> (width: Int, height: Int) {
    let long = max(width, height)
    guard long > longEdge, long > 0 else { return (width & ~1, height & ~1) }
    let s = Double(longEdge) / Double(long)
    func even(_ v: Int) -> Int { max(2, Int((Double(v) * s / 2).rounded()) * 2) }
    return (even(width), even(height))
}

public func frameName(_ n: Int) -> String { String(format: "%06d.png", n) }

// ——— masks

/// A binary mask, row major, top row first; a pixel is 0 or 255 (what the PNG holds).
public struct Mask: Equatable, Sendable {
    public let width: Int, height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]? = nil) {
        self.width = width; self.height = height
        self.pixels = pixels ?? [UInt8](repeating: 0, count: width * height)
        precondition(self.pixels.count == width * height, "mask size")
    }

    /// A box drawn as a mask (the start frame's mask when nothing better is known).
    public static func box(_ b: Box, width: Int, height: Int) -> Mask {
        var m = Mask(width: width, height: height)
        let x0 = max(0, Int((b.x * Double(width)).rounded())), x1 = min(width, Int((b.maxX * Double(width)).rounded()))
        let y0 = max(0, Int((b.y * Double(height)).rounded())), y1 = min(height, Int((b.maxY * Double(height)).rounded()))
        guard x1 > x0, y1 > y0 else { return m }
        for y in y0..<y1 { for x in x0..<x1 { m.pixels[y * width + x] = 255 } }
        return m
    }

    /// A soft or logit map sampled to `outWidth × outHeight` (nearest), in where value > threshold.
    /// Used for Vision's scaled float masks and SAM's low-resolution logits.
    public static func threshold(width: Int, height: Int, outWidth: Int, outHeight: Int, above threshold: Float,
                                 _ value: (Int, Int) -> Float) -> Mask {
        var m = Mask(width: outWidth, height: outHeight)
        for y in 0..<outHeight {
            let sy = min(height - 1, y * height / outHeight)
            for x in 0..<outWidth {
                let sx = min(width - 1, x * width / outWidth)
                if value(sx, sy) > threshold { m.pixels[y * outWidth + x] = 255 }
            }
        }
        return m
    }

    public var area: Int { pixels.reduce(0) { $0 + ($1 >= 128 ? 1 : 0) } }
    public var isEmpty: Bool { !pixels.contains { $0 >= 128 } }

    public func resized(width w: Int, height h: Int) -> Mask {
        if w == width && h == height { return self }
        var m = Mask(width: w, height: h)
        for y in 0..<h {
            let sy = min(height - 1, y * height / h)
            for x in 0..<w { m.pixels[y * w + x] = pixels[sy * width + min(width - 1, x * width / w)] }
        }
        return m
    }

    /// IoU with another mask, resampled to this one's size if it differs. Both empty: 0 (nothing
    /// to hold on to, unlike score.py, which scores agreement).
    public func iou(_ other: Mask) -> Double {
        let o = other.resized(width: width, height: height)
        var inter = 0, union = 0
        for i in 0..<pixels.count {
            let a = pixels[i] >= 128, b = o.pixels[i] >= 128
            if a && b { inter += 1 }
            if a || b { union += 1 }
        }
        return union > 0 ? Double(inter) / Double(union) : 0
    }

    /// IoU of the mask with a box drawn at the same size.
    public func iou(_ box: Box) -> Double { iou(Mask.box(box, width: width, height: height)) }

    /// The tightest normalized box around the mask, nil when empty.
    public var boundingBox: Box? {
        var x0 = width, y0 = height, x1 = -1, y1 = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] >= 128 {
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            }
        }
        guard x1 >= 0 else { return nil }
        return Box(x: Double(x0) / Double(width), y: Double(y0) / Double(height),
                   w: Double(x1 - x0 + 1) / Double(width), h: Double(y1 - y0 + 1) / Double(height))
    }

    public func contains(_ p: Point) -> Bool {
        let x = min(width - 1, max(0, Int(p.x * Double(width)))), y = min(height - 1, max(0, Int(p.y * Double(height))))
        return pixels[y * width + x] >= 128
    }
}

/// Vision's instance map: one byte per pixel, 0 = background, k = instance k
/// (VNInstanceMaskObservation.instanceMask, at the observation's own low resolution).
public struct LabelMap: Sendable {
    public let width: Int, height: Int
    public let labels: [UInt8]

    public init(width: Int, height: Int, labels: [UInt8]) {
        precondition(labels.count == width * height, "label map size")
        self.width = width; self.height = height; self.labels = labels
    }

    public var ids: [Int] { Array(Set(labels.map(Int.init))).filter { $0 != 0 }.sorted() }

    public func instance(_ id: Int) -> Mask {
        Mask(width: width, height: height, pixels: labels.map { Int($0) == id ? 255 : 0 })
    }
}

/// How each tracker chooses one instance. Each returns nil when nothing qualifies: the frame is
/// written as an empty mask (the object counts as lost) instead of taking the wrong one.
public enum Pick {
    /// The instance with the highest IoU with the box; nil below `minimum`.
    public static func byBox(_ map: LabelMap, box: Box, minimum: Double = 0.05) -> Int? {
        best(map.ids, minimum) { map.instance($0).iou(box) }
    }

    /// The instance under the point; nil on background.
    public static func byPoint(_ map: LabelMap, point: Point) -> Int? {
        let x = min(map.width - 1, max(0, Int(point.x * Double(map.width))))
        let y = min(map.height - 1, max(0, Int(point.y * Double(map.height))))
        let id = Int(map.labels[y * map.width + x])
        return id == 0 ? nil : id
    }

    /// The instance with the highest IoU with the last mask the tracker held; nil below `minimum`.
    public static func byPrevious(_ map: LabelMap, previous: Mask, minimum: Double = 0.01) -> Int? {
        let prev = previous.resized(width: map.width, height: map.height)
        return best(map.ids, minimum) { map.instance($0).iou(prev) }
    }

    /// The first frame of a tracker: by the prompt.
    public static func byPrompt(_ map: LabelMap, prompt: Prompt) -> Int? {
        switch prompt {
        case .box(let b): return byBox(map, box: b)
        case .point(let p): return byPoint(map, point: p)
        }
    }

    static func best(_ ids: [Int], _ minimum: Double, _ score: (Int) -> Double) -> Int? {
        var pick: Int?, top = minimum
        for id in ids {
            let s = score(id)
            if s >= top, pick == nil || s > top { pick = id; top = s }
        }
        return pick
    }
}

// ——— sam2-coreml (experimental; Tools/masklab/README.md states the assumed model interface)

/// SAM's prompt as points in the image encoder's input space (`side` × `side`, stretched from the
/// frame) with SAM's point labels: 1 = on the object, 2 / 3 = a box's top-left / bottom-right corner.
public enum SAMPrompt {
    public static func points(_ prompt: Prompt, side: Double) -> (xy: [Float], labels: [Int32]) {
        switch prompt {
        case .point(let p):
            return ([Float(p.x * side), Float(p.y * side)], [1])
        case .box(let b):
            return ([Float(b.x * side), Float(b.y * side), Float(b.maxX * side), Float(b.maxY * side)], [2, 3])
        }
    }

    /// The next frame's prompt: the last mask's box, grown by `margin` of its size on each side so
    /// an object that moved a little is still inside it. nil for an empty mask.
    public static func follow(_ mask: Mask, margin: Double = 0.1) -> Prompt? {
        guard let b = mask.boundingBox else { return nil }
        let g = Box(x: b.x - b.w * margin, y: b.y - b.h * margin, w: b.w * (1 + 2 * margin), h: b.h * (1 + 2 * margin))
        return .box(g.clamped())
    }

    /// Which of the decoder's candidate masks to keep: the highest predicted IoU score.
    public static func best(_ scores: [Float]) -> Int? {
        scores.indices.max { scores[$0] < scores[$1] }
    }
}

// ——— timing.json

public struct Timing: Codable, Sendable {
    public struct Device: Codable, Sendable {
        public var model: String, os: String, cores: Int, memoryGB: Double
        enum CodingKeys: String, CodingKey { case model, os, cores, memoryGB = "memory_gb" }
        public init(model: String, os: String, cores: Int, memoryGB: Double) {
            self.model = model; self.os = os; self.cores = cores; self.memoryGB = memoryGB
        }
    }

    public var version = 1
    public var tracker: String
    public var clip: String
    public var startFrame: Int
    /// Frames this run wrote a mask for (start frame included).
    public var frames = 0
    /// Wall clock from the first frame decoded at `startFrame` to the last mask written:
    /// decode, tracker and PNG writes. Frames before the start are decoded and skipped, untimed.
    public var totalMs = 0.0
    /// Per frame, the tracker's own work (Vision / Core ML and picking), no decode, no PNG write.
    public var perFrameMs: [Double] = []
    /// Per frame, the decode of that frame at the proxy size.
    public var decodeMs: [Double] = []
    /// Frames written as an empty mask (nothing picked: the object counts as lost).
    public var lost: [Int] = []
    /// vision-box: the tracker's confidence per frame (1 on the start frame).
    public var confidence: [Double]?
    public var proxy: [Int]
    public var source: [Int]
    public var prompt: [String: [Double]]
    public var model: String?
    public var device: Device

    enum CodingKeys: String, CodingKey {
        case version, tracker, clip, frames, lost, confidence, proxy, source, prompt, model, device
        case startFrame = "start_frame", totalMs = "total_ms", perFrameMs = "per_frame_ms", decodeMs = "decode_ms"
    }

    public init(tracker: Tracker, clip: String, startFrame: Int, prompt: Prompt, proxy: [Int], source: [Int],
                model: String?, device: Device) {
        self.tracker = tracker.rawValue; self.clip = clip; self.startFrame = startFrame
        self.proxy = proxy; self.source = source; self.model = model; self.device = device
        switch prompt {
        case .box(let b): self.prompt = ["box": [b.x, b.y, b.w, b.h]]
        case .point(let p): self.prompt = ["point": [p.x, p.y]]
        }
        if tracker == .visionBox { confidence = [] }
    }

    public func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
}
