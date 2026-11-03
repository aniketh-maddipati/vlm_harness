// masklab-iterative: Vision's prompted segmenter (GenerateIterativeSegmentationRequest, macOS 27) on one image, timed.
//
//   masklab-iterative --status                         asset status (ready / notReady / downloading / error)
//   masklab-iterative --download                       download the model assets (Vision decides where they go)
//   masklab-iterative IMAGE --out PREFIX [--quality fast|balanced|accurate]
//       (--seed-point x,y | --seed-box x,y,w,h | --seed-scribble STROKE.png [--scribble-format 8|f32]
//        [--scribble-own-size]) [--add x,y]… [--remove x,y]…
//
// Coordinates are fractions of the image from its top left (the mask lab's convention); Vision's own are from the
// bottom left, so they are flipped here. Writes PREFIX-0.png after the seed and PREFIX-<k>.png after each added
// point (in the order given: all --add, then all --remove), and prints one JSON line: ms for the seed request and
// for each request after a point was added, so whether a point re-runs the whole model shows in the numbers.
//
//   swiftc -O -o masklab-iterative Tools/masklab/iterative/main.swift
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

struct Usage: Error, CustomStringConvertible { var description: String }

func nums(_ s: String, _ n: Int) throws -> [Double] {
    let v = s.split(separator: ",").compactMap { Double($0) }
    guard v.count == n else { throw Usage(description: "want \(n) numbers, got \(s)") }
    return v
}

func point(_ v: [Double]) -> NormalizedPoint { NormalizedPoint(x: v[0], y: 1 - v[1]) }

func load(_ path: String) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw Usage(description: "can't read \(path)") }
    return img
}

func save(_ img: CGImage, _ path: String) throws {
    guard let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw Usage(description: "can't write \(path)") }
    CGImageDestinationAddImage(dst, img, nil)
    guard CGImageDestinationFinalize(dst) else { throw Usage(description: "can't write \(path)") }
}

func ms(_ t0: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - t0
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

@main
struct Main {
    static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) } catch {
            FileHandle.standardError.write("masklab-iterative: \(error)\n".data(using: .utf8)!)
            exit(2)
        }
    }

    static func run(_ a: [String]) async throws {
        if a.first == "--status" || a.first == "--download" {
            let r = GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5))
            if a.first == "--download" {
                let t0 = ContinuousClock.now
                try await r.downloadAssets()
                print("{\"downloaded_ms\": \(ms(t0))}")
            }
            print("{\"status\": \"\(await r.assetStatus)\"}")
            return
        }
        if a.first == "--track" { try await track(Array(a.dropFirst())); return }
        var image: String?, out: String?, quality = "balanced", seedPoint: [Double]?, seedBox: [Double]?
        var adds: [[Double]] = [], removes: [[Double]] = []
        var scribble: String?, scribbleFormat = "8", scribbleAtImageSize = true
        var i = 0
        func next() throws -> String { i += 1; guard i < a.count else { throw Usage(description: "\(a[i - 1]) needs a value") }; return a[i] }
        while i < a.count {
            switch a[i] {
            case "--out": out = try next()
            case "--quality": quality = try next()
            case "--seed-point": seedPoint = try nums(try next(), 2)
            case "--seed-box": seedBox = try nums(try next(), 4)
            case "--add": adds.append(try nums(try next(), 2))
            case "--remove": removes.append(try nums(try next(), 2))
            case "--seed-scribble": scribble = try next()
            case "--scribble-format": scribbleFormat = try next()
            case "--scribble-own-size": scribbleAtImageSize = false
            default: image = a[i]
            }
            i += 1
        }
        guard let image, let out else { throw Usage(description: "IMAGE and --out are needed") }
        let cg = try load(image)
        let req: GenerateIterativeSegmentationRequest
        if let s = scribble {
            // A stroke drawn as a mask (PNG, white = stroke), handed over as a one-channel buffer. The SDK documents
            // neither the format nor the values, so `--scribble-format` tries them: 8 (OneComponent8, stroke 255),
            // f32 (OneComponent32Float, stroke 1.0), at the image's size or the stroke file's own.
            let stroke = try load(s)
            let w = scribbleAtImageSize ? cg.width : stroke.width, h = scribbleAtImageSize ? cg.height : stroke.height
            let f32 = scribbleFormat == "f32"
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, f32 ? kCVPixelFormatType_OneComponent32Float : kCVPixelFormatType_OneComponent8,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
            guard let pb else { throw Usage(description: "can't make the scribble buffer") }
            CVPixelBufferLockBaseAddress(pb, [])
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(stroke, in: CGRect(x: 0, y: 0, width: w, height: h))
            let src = ctx.data!.assumingMemoryBound(to: UInt8.self)
            let base = CVPixelBufferGetBaseAddress(pb)!, row = CVPixelBufferGetBytesPerRow(pb)
            for y in 0..<h {
                for x in 0..<w {
                    let v = src[y * w + x]
                    if f32 { base.advanced(by: y * row).assumingMemoryBound(to: Float.self)[x] = Float(v) / 255 }
                    else { base.advanced(by: y * row).assumingMemoryBound(to: UInt8.self)[x] = v }
                }
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            req = GenerateIterativeSegmentationRequest(seedScribbleBuffer: CVReadOnlyPixelBuffer(unsafeBuffer: pb))
        } else if let b = seedBox {
            req = GenerateIterativeSegmentationRequest(seedBox: NormalizedRect(x: b[0], y: 1 - b[1] - b[3], width: b[2], height: b[3]))
        } else if let p = seedPoint {
            req = GenerateIterativeSegmentationRequest(seedPoint: point(p))
        } else { throw Usage(description: "--seed-point, --seed-box or --seed-scribble") }
        req.qualityLevel = ["fast": .fast, "accurate": .accurate][quality] ?? .balanced
        var times: [Double] = []
        func step(_ k: Int) async throws {
            let t0 = ContinuousClock.now
            let obs = try await req.perform(on: cg)
            times.append(ms(t0))
            if let obs { try save(try obs.cgImage, "\(out)-\(k).png") }
        }
        try await step(0)
        var k = 1
        for p in adds { try req.addIncludedPoint(point(p)); try await step(k); k += 1 }
        for p in removes { try req.addExcludedPoint(point(p)); try await step(k); k += 1 }
        let size = "[\(cg.width), \(cg.height)]"
        print("{\"image\": \"\(image)\", \"quality\": \"\(quality)\", \"size\": \(size), \"ms\": \(times)}")
    }

    /// B2: a box per frame (another tracker's), the mask from the prompted segmenter, in one process.
    ///   masklab-iterative --track BOXES.json --out DIR [--quality q] [--tracker name]
    /// BOXES.json: {"clip": name, "frames": [{"n": 12, "image": "/…/00012.jpg", "box": [x,y,w,h] | null}, …]}
    /// Writes DIR/<n:06d>.png for every listed frame (empty where box is null) and DIR/timing.json.
    static func track(_ a: [String]) async throws {
        var boxes: String?, out: String?, quality = "balanced", tracker = "iterative-on-box"
        var i = 0
        func next() throws -> String { i += 1; guard i < a.count else { throw Usage(description: "\(a[i - 1]) needs a value") }; return a[i] }
        while i < a.count {
            switch a[i] {
            case "--out": out = try next()
            case "--quality": quality = try next()
            case "--tracker": tracker = try next()
            default: boxes = a[i]
            }
            i += 1
        }
        guard let boxes, let out else { throw Usage(description: "--track BOXES.json --out DIR") }
        struct Job: Decodable { struct Frame: Decodable { var n: Int; var image: String; var box: [Double]? }; var clip: String; var frames: [Frame] }
        let job = try JSONDecoder().decode(Job.self, from: Data(contentsOf: URL(fileURLWithPath: boxes)))
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let t0 = ContinuousClock.now
        var per: [Double] = [], ran = 0, first = job.frames.first?.n ?? 0
        var size = (0, 0)
        for f in job.frames {
            let cg = try load(f.image)
            size = (cg.width, cg.height)
            let path = "\(out)/" + String(format: "%06d.png", f.n)
            guard let b = f.box, b[2] > 0, b[3] > 0 else {
                let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                try save(ctx.makeImage()!, path)
                per.append(0)
                continue
            }
            let req = GenerateIterativeSegmentationRequest(seedBox: NormalizedRect(x: b[0], y: 1 - b[1] - b[3], width: b[2], height: b[3]))
            req.qualityLevel = ["fast": .fast, "accurate": .accurate][quality] ?? .balanced
            let t = ContinuousClock.now
            let obs = try await req.perform(on: cg)
            per.append(ms(t))
            ran += 1
            if let obs { try save(try obs.cgImage, path) }
        }
        first = min(first, job.frames.map(\.n).min() ?? 0)
        let timing: [String: Any] = ["tracker": tracker, "clip": job.clip, "start_frame": first, "frames": job.frames.count,
                                     "total_ms": ms(t0), "per_frame_ms": per, "model_frames": ran, "quality": quality,
                                     "proxy": [size.0, size.1]]
        try JSONSerialization.data(withJSONObject: timing).write(to: URL(fileURLWithPath: "\(out)/timing.json"))
        print("\(job.clip): \(job.frames.count) frames, model on \(ran), \(String(format: "%.1f", Double(job.frames.count) / (ms(t0) / 1000))) fps")
    }
}
