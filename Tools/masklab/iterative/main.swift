// masklab-iterative: Vision's prompted segmenter (GenerateIterativeSegmentationRequest, macOS 27) on one image, timed.
//
//   masklab-iterative --status                         asset status (ready / notReady / downloading / error)
//   masklab-iterative --download                       download the model assets (Vision decides where they go)
//   masklab-iterative IMAGE --out PREFIX [--quality fast|balanced|accurate]
//       (--seed-point x,y | --seed-box x,y,w,h) [--add x,y]… [--remove x,y]…
//
// Coordinates are fractions of the image from its top left (the mask lab's convention); Vision's own are from the
// bottom left, so they are flipped here. Writes PREFIX-0.png after the seed and PREFIX-<k>.png after each added
// point (in the order given: all --add, then all --remove), and prints one JSON line: ms for the seed request and
// for each request after a point was added, so whether a point re-runs the whole model shows in the numbers.
//
//   swiftc -O -o masklab-iterative Tools/masklab/iterative/main.swift
import CoreGraphics
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
        var image: String?, out: String?, quality = "balanced", seedPoint: [Double]?, seedBox: [Double]?
        var adds: [[Double]] = [], removes: [[Double]] = []
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
            default: image = a[i]
            }
            i += 1
        }
        guard let image, let out else { throw Usage(description: "IMAGE and --out are needed") }
        let cg = try load(image)
        let req: GenerateIterativeSegmentationRequest
        if let b = seedBox {
            req = GenerateIterativeSegmentationRequest(seedBox: NormalizedRect(x: b[0], y: 1 - b[1] - b[3], width: b[2], height: b[3]))
        } else if let p = seedPoint {
            req = GenerateIterativeSegmentationRequest(seedPoint: point(p))
        } else { throw Usage(description: "--seed-point or --seed-box") }
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
}
