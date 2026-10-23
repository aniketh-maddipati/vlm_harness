import AppKit
import CoreGraphics
import Foundation
import ImageIO

// The sky mask on stills (Tools/masklab/README.md, "Sky"): the app's own finder (SetsMasks + LookMasks,
// compiled in from Lumina/Sets) on each photo's embedded preview at 1024 px, never a RAW decode.
//
//   masklab-sky <out dir> <photo> …      (or @list: one path a line)
//
// Writes <out>/<n>-<name>.jpg (the photo with the sky the app would offer tinted blue and every other shape
// outlined), <out>/sheet-<k>.jpg (twelve at a time, for a look) and <out>/report.json: per photo the
// classifier's top labels, the gate's sky score (nil: the app offers no sky), the sky's area as offered,
// the area the finder gives with the gate open, and the time taken.

func image(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageIfAbsent: true, kCGImageSourceCreateThumbnailWithTransform: true,
                              kCGImageSourceThumbnailMaxPixelSize: SetsMasks.pixels]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
}

func jpeg(_ img: CGImage, to url: URL) {
    guard let d = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    CGImageDestinationFinalize(d)
}

func overlay(_ img: CGImage, sky: LookMasks.Plane?, shapes: [LookMasks.Found], long: Int, title: String) -> CGImage? {
    let s = Double(long) / Double(max(img.width, img.height)), w = Int(Double(img.width) * s), h = Int(Double(img.height) * s)
    guard let cx = CGContext(data: nil, width: w, height: h + 22, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    cx.setFillColor(CGColor(gray: 0.1, alpha: 1)); cx.fill(CGRect(x: 0, y: 0, width: w, height: h + 22))
    cx.draw(img, in: CGRect(x: 0, y: 22, width: w, height: h))
    if let sky {
        let m = LookMasks.resized(sky, width: w, height: h)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w { let v = m.values[y * w + x], i = (y * w + x) * 4; px[i + 2] = UInt8(min(255, v * 255)); px[i + 3] = UInt8(min(255, v * 140)) } }
        if let p = CGDataProvider(data: Data(px) as CFData),
           let mi = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            cx.draw(mi, in: CGRect(x: 0, y: 22, width: w, height: h))
        }
    }
    for f in shapes where f.kind != .sky && f.kind != .background {
        cx.setStrokeColor(f.kind == .person ? CGColor(red: 1, green: 0.5, blue: 0.3, alpha: 1) : CGColor(red: 1, green: 0.82, blue: 0.48, alpha: 1)); cx.setLineWidth(1.5)
        for loop in f.outline where loop.count > 2 {
            cx.beginPath(); cx.move(to: CGPoint(x: loop[0].x * Double(w), y: 22 + (1 - loop[0].y) * Double(h)))
            for p in loop.dropFirst() { cx.addLine(to: CGPoint(x: p.x * Double(w), y: 22 + (1 - p.y) * Double(h))) }
            cx.closePath(); cx.strokePath()
        }
    }
    let ns = NSGraphicsContext(cgContext: cx, flipped: false); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    (title as NSString).draw(at: NSPoint(x: 6, y: 5), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white])
    NSGraphicsContext.restoreGraphicsState()
    return cx.makeImage()
}

let args = CommandLine.arguments.dropFirst()
guard let outPath = args.first, args.count >= 2 else { FileHandle.standardError.write("usage: masklab-sky <out dir> <photo> …\n".data(using: .utf8)!); exit(2) }
let out = URL(fileURLWithPath: outPath, isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var report: [[String: Any]] = [], tiles: [CGImage] = [], sheets = 0
func sheet() {
    guard !tiles.isEmpty else { return }
    let cols = 4, tw = 384, th = tiles.map(\.height).max() ?? 240, rows = (tiles.count + cols - 1) / cols
    guard let cx = CGContext(data: nil, width: cols * tw, height: rows * th, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    cx.setFillColor(CGColor(gray: 0.1, alpha: 1)); cx.fill(CGRect(x: 0, y: 0, width: cols * tw, height: rows * th))
    for (i, t) in tiles.enumerated() { cx.draw(t, in: CGRect(x: (i % cols) * tw, y: (rows - 1 - i / cols) * th + (th - t.height), width: t.width, height: t.height)) }
    sheets += 1
    if let im = cx.makeImage() { jpeg(im, to: out.appendingPathComponent(String(format: "sheet-%02d.jpg", sheets))) }
    tiles = []
}
let paths = args.dropFirst().flatMap { a -> [String] in
    a.hasPrefix("@") ? ((try? String(contentsOfFile: String(a.dropFirst()), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) : [a]
}
for (n, path) in paths.enumerated() {
    let url = URL(fileURLWithPath: path), name = url.lastPathComponent, t0 = Date()
    guard let img = image(url) else { report.append(["file": path, "error": "unreadable"]); continue }
    let labels = SetsMasks.scene(img) ?? [:]
    let gate = LookMasks.skyScore(labels)
    let found = SetsMasks.masks(img) ?? []
    let offered = found.first { $0.kind == .sky }
    let c = SetsMasks.rgb(img), open = c.flatMap { LookMasks.sky(red: $0.red, green: $0.green, blue: $0.blue) }
    let openArea = open.map { p in Double(p.values.reduce(0) { $0 + ($1 >= 0.5 ? 1 : 0) }) / Double(max(1, p.values.count)) }
    let skyPlane = offered != nil ? open : nil
    let top = labels.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key) \(String(format: "%.2f", $0.value))" }
    let title = "\(n + 1) \(name) · gate \(gate.map { String(format: "%.2f", $0) } ?? "–") · sky \(offered.map { String(format: "%.0f%%", $0.area * 100) } ?? "none") · open \(openArea.map { String(format: "%.0f%%", $0 * 100) } ?? "none")"
    if let o = overlay(img, sky: skyPlane, shapes: found, long: 768, title: title) { jpeg(o, to: out.appendingPathComponent(String(format: "%03d-%@.jpg", n + 1, name))) }
    if let o = overlay(img, sky: skyPlane, shapes: found, long: 384, title: title) { tiles.append(o); if tiles.count == 12 { sheet() } }
    report.append(["n": n + 1, "file": path, "labels": top, "gate": gate ?? NSNull(), "skyArea": offered?.area ?? NSNull(), "openArea": openArea ?? NSNull(),
                   "shapes": found.map { "\($0.id) \(String(format: "%.0f%%", $0.area * 100))" }, "seconds": Date().timeIntervalSince(t0)])
    print(title)
}
sheet()
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try data.write(to: out.appendingPathComponent("report.json"))
print("report \(out.appendingPathComponent("report.json").path) · \(sheets) sheets")
