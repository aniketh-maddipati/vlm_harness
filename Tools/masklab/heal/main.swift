// masklab-heal: Skim's own Remove (SkimPlate's median clean plate, as SkimPatch makes it) on a folder of frames, so
// heal_score.py can score it next to the model healers. Measures only; nothing here is in the app.
//
//   masklab-heal FRAMES_DIR HOLES_DIR OUT_DIR [--grow PX]
//
// FRAMES_DIR: the clip's frames (00000.jpg …); HOLES_DIR: one 8-bit PNG per frame, same number, white in the hole
// (make_holes.py, or a tracker's masks). Like SkimPatch: the crop around every hole's box (SkimPlate.crop, with
// SkimPlate.pad), up to SkimPlate.maxFrames frames spread over the clip (SkimPlate.picks), each hole grown by
// SkimPlate.margin (+ --grow) pixels, the plate from SkimPlate.plate, the camera's shake from SkimPlate.shake. Writes
// OUT_DIR/<n:06d>.png: each frame with the plate inside its own (grown) hole, and OUT_DIR/plate.json: shake, unseen,
// SkimPlate.refusal (what the app would say: a moving camera or a scene never seen is refused there), and timings.
//
//   swiftc -O -o masklab-heal Lumina/Sets/Look/LookMasks.swift Lumina/Sets/Video/SkimPlate.swift Tools/masklab/heal/Stub.swift Tools/masklab/heal/main.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Usage: Error, CustomStringConvertible { var description: String }

func load(_ path: String) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}

/// RGBA bytes of an image at its own size.
func rgba(_ img: CGImage) -> [UInt8] {
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return px
}

/// The hole as booleans at (w, h), grown by `grow` pixels (a square dilation, done as two 1-D passes).
func hole(_ path: String, w: Int, h: Int, grow: Int) -> [Bool] {
    guard let img = load(path) else { return [Bool](repeating: false, count: w * h) }
    var g = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(data: &g, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.interpolationQuality = .none
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var m = g.map { $0 >= 128 }
    guard grow > 0 else { return m }
    var t = m
    for y in 0..<h { for x in 0..<w where m[y * w + x] { for d in max(0, x - grow)...min(w - 1, x + grow) { t[y * w + d] = true } } }
    m = t
    for y in 0..<h { for x in 0..<w where t[y * w + x] { for d in max(0, y - grow)...min(h - 1, y + grow) { m[d * w + x] = true } } }
    return m
}

func save(_ px: [UInt8], w: Int, h: Int, to path: String) throws {
    var p = px
    let ctx = CGContext(data: &p, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    guard let img = ctx.makeImage(),
          let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw Usage(description: "can't write \(path)") }
    CGImageDestinationAddImage(dst, img, nil)
    guard CGImageDestinationFinalize(dst) else { throw Usage(description: "can't write \(path)") }
}

func frameFiles(_ dir: String) -> [Int: String] {
    var out: [Int: String] = [:]
    for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
        let stem = (f as NSString).deletingPathExtension, ext = (f as NSString).pathExtension.lowercased()
        if let n = Int(stem), ["png", "jpg", "jpeg"].contains(ext) { out[n] = dir + "/" + f }
    }
    return out
}

func ms(_ t: ContinuousClock.Instant) -> Double {
    let d = ContinuousClock.now - t
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

let a = Array(CommandLine.arguments.dropFirst())
guard a.count >= 3 else { FileHandle.standardError.write("usage: masklab-heal FRAMES HOLES OUT [--grow PX]\n".data(using: .utf8)!); exit(2) }
let extra = a.firstIndex(of: "--grow").flatMap { a.count > $0 + 1 ? Int(a[$0 + 1]) : nil } ?? 0
let frames = frameFiles(a[0]), holes = frameFiles(a[1]), out = a[2]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let ns = frames.keys.sorted()
guard let first = ns.first, let f0 = load(frames[first]!) else { FileHandle.standardError.write("no frames\n".data(using: .utf8)!); exit(2) }
let W = f0.width, H = f0.height, grow = SkimPlate.margin + extra
let t0 = ContinuousClock.now

// Every frame's grown hole, and the box around each.
var masks: [Int: [Bool]] = [:], boxes: [SkimPlate.Box] = []
for n in ns {
    let m = holes[n].map { hole($0, w: W, h: H, grow: grow) } ?? [Bool](repeating: false, count: W * H)
    masks[n] = m
    var x0 = W, y0 = H, x1 = -1, y1 = -1
    for y in 0..<H { for x in 0..<W where m[y * W + x] { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    if x1 >= 0 { boxes.append(.init(x: Double(x0) / Double(W), y: Double(y0) / Double(H), w: Double(x1 - x0 + 1) / Double(W), h: Double(y1 - y0 + 1) / Double(H))) }
}
guard let crop = SkimPlate.crop(boxes, width: W, height: H) else { FileHandle.standardError.write("no hole\n".data(using: .utf8)!); exit(2) }

// The plate from up to maxFrames frames spread over the clip, at the crop.
let picks = SkimPlate.picks(frames: ns.count).map { ns[$0] }
var cropRGB: [[UInt8]] = [], cropMasks: [LookMasks.Plane] = []
var full: [Int: [UInt8]] = [:]
for n in picks {
    guard let img = load(frames[n]!) else { continue }
    let px = rgba(img); full[n] = px
    var rgb = [UInt8](repeating: 0, count: crop.w * crop.h * 3)
    var plane = LookMasks.Plane(width: crop.w, height: crop.h)
    let m = masks[n]!
    for y in 0..<crop.h {
        for x in 0..<crop.w {
            let si = (crop.y + y) * W + crop.x + x, di = y * crop.w + x
            // Inside the hole the frame stands for the thing being removed: a made-up hole still has the true
            // background under it, which the plate's fallback (the median of every frame, for pixels no frame shows)
            // would copy back. Mid-grey there, so only what other frames really show can fill it.
            if m[si] { rgb[di * 3] = 128; rgb[di * 3 + 1] = 128; rgb[di * 3 + 2] = 128 }
            else { rgb[di * 3] = px[si * 4]; rgb[di * 3 + 1] = px[si * 4 + 1]; rgb[di * 3 + 2] = px[si * 4 + 2] }
            plane.values[di] = m[si] ? 1 : 0
        }
    }
    cropRGB.append(rgb); cropMasks.append(plane)
}
let tPlate = ContinuousClock.now
guard let plate = SkimPlate.plate(frames: cropRGB, masks: cropMasks, width: crop.w, height: crop.h) else { exit(3) }
let plateMs = ms(tPlate)
let shake = SkimPlate.shake(frames: cropRGB, masks: cropMasks, plate: plate, width: crop.w, height: crop.h)

// Each frame with the plate in its own hole.
for n in ns {
    var px = full[n] ?? rgba(load(frames[n]!)!)
    let m = masks[n]!
    for y in 0..<crop.h {
        for x in 0..<crop.w {
            let si = (crop.y + y) * W + crop.x + x, di = y * crop.w + x
            if m[si] { px[si * 4] = plate.rgb[di * 3]; px[si * 4 + 1] = plate.rgb[di * 3 + 1]; px[si * 4 + 2] = plate.rgb[di * 3 + 2] }
        }
    }
    try save(px, w: W, h: H, to: out + "/" + String(format: "%06d.png", n))
}
let total = ms(t0)
let report: [String: Any] = ["frames": ns.count, "plate_frames": picks.count, "crop": [crop.x, crop.y, crop.w, crop.h],
                             "grow": grow, "shake": shake, "unseen": plate.unseen,
                             "refusal": SkimPlate.refusal(shake: shake, unseen: plate.unseen) ?? NSNull(),
                             "plate_ms": plateMs, "total_ms": total, "fps": Double(ns.count) / (total / 1000)]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: out + "/plate.json"))
print("\((a[0] as NSString).lastPathComponent): \(ns.count) frames, shake \(String(format: "%.1f", shake)), unseen \(String(format: "%.1f", plate.unseen * 100))%, \(String(format: "%.1f", Double(ns.count) / (total / 1000))) fps")
