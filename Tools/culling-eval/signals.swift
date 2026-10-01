// Candidate "which frame" signals for the culling eval, computed on this Mac from each RAW's
// embedded preview (ImageIO thumbnail, long edge 1600): Vision's face capture quality, face
// landmarks (eye openness), attention saliency, image aesthetics (macOS 15+), Core Image's
// smile / blink detector, and Laplacian-variance sharpness on the whole frame, the centre, the
// salient box and the largest face. Nothing leaves the Mac; the output is numbers per photo.
//
//   swiftc -O Tools/culling-eval/signals.swift -o /tmp/signals
//   /tmp/signals <list.txt: one "id<TAB>absolute path" per line> <out.jsonl> [workers]
import CoreImage
import Foundation
import ImageIO
import Vision

struct Gray { let w: Int, h: Int; let px: [UInt8] }

func load(_ url: URL, maxPixel: Int = 1600) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageIfAbsent: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                                 kCGImageSourceCreateThumbnailWithTransform: true]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}

func gray(_ img: CGImage, longEdge: Int = 1024) -> Gray? {
    let s = Double(longEdge) / Double(max(img.width, img.height))
    let w = max(2, Int(Double(img.width) * s)), h = max(2, Int(Double(img.height) * s))
    var px = [UInt8](repeating: 0, count: w * h)
    let ok = px.withUnsafeMutableBytes { buf -> Bool in
        guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return ok ? Gray(w: w, h: h, px: px) : nil
}

/// Laplacian variance, mean luma and clipped fractions inside a normalized rect (origin top-left).
func stats(_ g: Gray, _ r: CGRect) -> (lap: Double, mean: Double, hi: Double, lo: Double) {
    let x0 = max(1, Int(r.minX * Double(g.w))), x1 = min(g.w - 1, Int(r.maxX * Double(g.w)))
    let y0 = max(1, Int(r.minY * Double(g.h))), y1 = min(g.h - 1, Int(r.maxY * Double(g.h)))
    guard x1 - x0 > 4, y1 - y0 > 4 else { return (0, 0, 0, 0) }
    var s = 0.0, s2 = 0.0, sum = 0.0, hi = 0.0, lo = 0.0, n = 0.0
    for y in y0..<y1 {
        for x in x0..<x1 {
            let i = y * g.w + x
            let v = Double(g.px[i])
            let l = 4 * v - Double(g.px[i - 1]) - Double(g.px[i + 1]) - Double(g.px[i - g.w]) - Double(g.px[i + g.w])
            s += l; s2 += l * l; sum += v; n += 1
            if v >= 250 { hi += 1 }
            if v <= 5 { lo += 1 }
        }
    }
    let m = s / n
    return (s2 / n - m * m, sum / n / 255, hi / n, lo / n)
}

/// Vision rects have their origin bottom-left; `stats` wants top-left.
func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height) }

/// Height / width of an eye's landmark outline in pixels: about 0.3 open, under 0.15 closed.
func eyeOpen(_ region: VNFaceLandmarkRegion2D?, face: CGRect, image: CGSize) -> Double? {
    guard let pts = region?.normalizedPoints, pts.count >= 4 else { return nil }
    let xs = pts.map { Double($0.x) * face.width * image.width }, ys = pts.map { Double($0.y) * face.height * image.height }
    let w = xs.max()! - xs.min()!, h = ys.max()! - ys.min()!
    return w > 0 ? h / w : nil
}

func signals(_ url: URL) -> [String: Any]? {
    guard let img = load(url), let g = gray(img) else { return nil }
    var out: [String: Any] = ["w": img.width, "h": img.height]
    let whole = stats(g, CGRect(x: 0, y: 0, width: 1, height: 1))
    let centre = stats(g, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    out["sharpAll"] = whole.lap; out["sharpCentre"] = centre.lap; out["lum"] = whole.mean; out["clipHi"] = whole.hi; out["clipLo"] = whole.lo

    let handler = VNImageRequestHandler(cgImage: img, options: [:])
    let quality = VNDetectFaceCaptureQualityRequest(), marks = VNDetectFaceLandmarksRequest(), sal = VNGenerateAttentionBasedSaliencyImageRequest()
    var requests: [VNRequest] = [quality, marks, sal]
    var aesthetics: VNRequest?
    if #available(macOS 15.0, *) { let a = VNCalculateImageAestheticsScoresRequest(); aesthetics = a; requests.append(a) }
    try? handler.perform(requests)

    if #available(macOS 15.0, *), let a = (aesthetics?.results as? [VNImageAestheticsScoresObservation])?.first {
        out["aesthetic"] = Double(a.overallScore); out["utility"] = a.isUtility
    }
    if let box = (sal.results?.first as? VNSaliencyImageObservation)?.salientObjects?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })?.boundingBox {
        let s = stats(g, flip(box))
        out["sharpSalient"] = s.lap; out["salientArea"] = Double(box.width * box.height); out["lumSalient"] = s.mean
    }
    let faces = (quality.results ?? []).sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }
    out["faces"] = faces.count
    if let f = faces.first {
        let s = stats(g, flip(f.boundingBox))
        out["faceArea"] = Double(f.boundingBox.width * f.boundingBox.height)
        out["sharpFace"] = s.lap; out["lumFace"] = s.mean; out["clipFace"] = s.hi
        let q = faces.compactMap { $0.faceCaptureQuality.map(Double.init) }
        if !q.isEmpty { out["faceQMax"] = q.max()!; out["faceQMean"] = q.reduce(0, +) / Double(q.count); out["faceQMin"] = q.min()!; out["faceQMain"] = Double(f.faceCaptureQuality ?? 0) }
    }
    let size = CGSize(width: img.width, height: img.height)
    let eyes = (marks.results ?? []).compactMap { f -> Double? in
        let l = eyeOpen(f.landmarks?.leftEye, face: f.boundingBox, image: size), r = eyeOpen(f.landmarks?.rightEye, face: f.boundingBox, image: size)
        return [l, r].compactMap { $0 }.min()
    }
    if !eyes.isEmpty { out["eyeOpenMin"] = eyes.min()!; out["eyeOpenMean"] = eyes.reduce(0, +) / Double(eyes.count) }

    // Core Image's detector: the only on-device smile / blink flags without a custom model.
    if let det = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) {
        let fs = det.features(in: CIImage(cgImage: img), options: [CIDetectorSmile: true, CIDetectorEyeBlink: true]).compactMap { $0 as? CIFaceFeature }
        if !fs.isEmpty {
            out["smiles"] = Double(fs.filter(\.hasSmile).count) / Double(fs.count)
            out["blinks"] = Double(fs.filter { $0.leftEyeClosed || $0.rightEyeClosed }.count) / Double(fs.count)
        }
    }
    return out
}

let args = CommandLine.arguments
guard args.count >= 3, let list = try? String(contentsOfFile: args[1], encoding: .utf8) else {
    FileHandle.standardError.write(Data("usage: signals <list.txt> <out.jsonl> [workers]\n".utf8)); exit(2)
}
let items = list.split(separator: "\n").compactMap { line -> (String, String)? in
    let p = line.split(separator: "\t", maxSplits: 1).map(String.init)
    return p.count == 2 ? (p[0], p[1]) : nil
}
let workers = args.count > 3 ? Int(args[3]) ?? 3 : 3
FileManager.default.createFile(atPath: args[2], contents: nil)
let out = FileHandle(forWritingAtPath: args[2])!
let lock = NSLock()
nonisolated(unsafe) var done = 0, failed = 0
let t0 = Date()
let queue = OperationQueue(); queue.maxConcurrentOperationCount = workers
for (id, path) in items {
    queue.addOperation {
        autoreleasepool {
            var row = signals(URL(fileURLWithPath: path)) ?? [:]
            let ok = !row.isEmpty
            row["id"] = id
            let data = (try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])) ?? Data("{}".utf8)
            lock.withLock {
                out.write(data); out.write(Data("\n".utf8))
                done += 1; if !ok { failed += 1 }
                if done % 100 == 0 { FileHandle.standardError.write(Data("\(done)/\(items.count) · \(Int(Date().timeIntervalSince(t0))) s\n".utf8)) }
            }
        }
    }
}
queue.waitUntilAllOperationsAreFinished()
FileHandle.standardError.write(Data("done \(done), unreadable \(failed), \(Int(Date().timeIntervalSince(t0))) s\n".utf8))
