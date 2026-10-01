import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Builds on-disk fixture folders for the import tests: real image files, not mocks.
enum Fixtures {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumina-fixtures")

    static func folder(_ name: String, _ build: (URL) throws -> Void) -> URL {
        let u = root.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: u)
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        try! build(u); return u
    }

    // MARK: writers
    static func image(_ w: Int, _ h: Int, seed: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let hue = CGFloat((seed * 47) % 360) / 360
        ctx.setFillColor(CGColor(red: hue, green: 0.5, blue: 1 - hue, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.8)); ctx.fill(CGRect(x: w / 10, y: h / 10, width: max(1, w / 5), height: max(1, h / 5)))
        return ctx.makeImage()!
    }

    /// Writes an image with optional EXIF (capture date, camera, exposure, orientation).
    static func write(_ url: URL, type: UTType = .jpeg, w: Int = 640, h: Int = 420, seed: Int = 1,
                      shot: Date? = nil, orientation: Int = 1, camera: (make: String, model: String)? = nil,
                      modified: Date? = nil) {
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        var props: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        var exif: [CFString: Any] = [:]
        if let shot {
            let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX")
            exif[kCGImagePropertyExifDateTimeOriginal] = f.string(from: shot)
        }
        if camera != nil { exif[kCGImagePropertyExifFNumber] = 2.8; exif[kCGImagePropertyExifExposureTime] = 1.0 / 250; exif[kCGImagePropertyExifISOSpeedRatings] = [800]; exif[kCGImagePropertyExifFocalLength] = 85 }
        if !exif.isEmpty { props[kCGImagePropertyExifDictionary] = exif }
        if let camera { props[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFMake: camera.make, kCGImagePropertyTIFFModel: camera.model] }
        CGImageDestinationAddImage(dest, image(w, h, seed: seed), props as CFDictionary)
        CGImageDestinationFinalize(dest)
        if let modified { try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
    }
    static func bytes(_ url: URL, _ n: Int, header: [UInt8] = []) {
        var d = Data(header); d.append(Data((0..<max(0, n - header.count)).map { UInt8(($0 * 131 + 7) & 255) })); try! d.write(to: url)
    }
    static func text(_ url: URL, _ s: String) { try! s.write(to: url, atomically: true, encoding: .utf8) }
    static func day(_ h: Int, _ m: Int = 0, _ s: Int = 0) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: h, minute: m, second: s))! }

    // MARK: the fixture set (mirrors Lumina Newbie Test.dc.html)
    /// 6 real photos + every kind of junk. Expect 6 added, every skip explained, system files silent. (R-10…R-13)
    static var messy: URL { folder("Card dump") { d in
        write(d.appendingPathComponent("a.jpg"), seed: 1)
        write(d.appendingPathComponent("b.png"), type: .png, w: 500, h: 500, seed: 2)
        write(d.appendingPathComponent("c.heic"), type: .heic, w: 600, h: 400, seed: 3)
        write(d.appendingPathComponent("d.gif"), type: .gif, w: 1, h: 1, seed: 4)
        write(d.appendingPathComponent("E.JPG"), w: 640, h: 480, seed: 5)
        write(d.appendingPathComponent("f-really-png.jpg"), type: .png, w: 300, h: 200, seed: 6)
        bytes(d.appendingPathComponent("clip.mp4"), 9000)
        text(d.appendingPathComponent("notes.txt"), "hello")
        bytes(d.appendingPathComponent("scan.pdf"), 3000, header: Array("%PDF-1.4".utf8))
        bytes(d.appendingPathComponent("photos.zip"), 2000, header: [0x50, 0x4B, 3, 4])
        bytes(d.appendingPathComponent(".DS_Store"), 600)
        bytes(d.appendingPathComponent("._a.jpg"), 4096)
        text(d.appendingPathComponent("a.xmp"), "<x:xmpmeta/>")
        try Data().write(to: d.appendingPathComponent("zero.jpg"))
        bytes(d.appendingPathComponent("broken.jpg"), 5000, header: [0xFF, 0xD8, 0xFF, 0xE0])
    } }
    static let messyExpectedAdded = 6

    static var onlyJunk: URL { folder("Docs") { d in text(d.appendingPathComponent("readme.txt"), "x"); bytes(d.appendingPathComponent("invoice.pdf"), 900, header: Array("%PDF".utf8)); bytes(d.appendingPathComponent("movie.mov"), 900) } }
    static var empty: URL { folder("Empty") { _ in } }
    static var nested: URL { folder("Trip") { d in
        let fm = FileManager.default
        for sub in ["Day 1", "Day 2", "Day 2/Raw"] { try fm.createDirectory(at: d.appendingPathComponent(sub), withIntermediateDirectories: true) }
        write(d.appendingPathComponent("Day 1/a.jpg"), seed: 1, shot: day(8, 0))
        write(d.appendingPathComponent("Day 1/b.jpg"), seed: 2, shot: day(8, 0, 4))
        write(d.appendingPathComponent("Day 2/c.jpg"), seed: 3, shot: day(9, 0))
        write(d.appendingPathComponent("e.jpg"), seed: 5, shot: day(18, 0))
    } }
    static var names: URL { folder("Names") { d in
        for (i, n) in ["🌅 sunset ✨.jpg", String(repeating: "a", count: 200) + ".jpg", "IMG 0001 (1).JPG", "שלום עולם.jpg", "noext", "   spaced   .jpg"].enumerated() {
            write(d.appendingPathComponent(n), seed: 20 + i, shot: day(9, i))
        }
    } }
    static var shapes: URL { folder("Shapes") { d in
        for (i, s) in [(1, 1), (4000, 100), (100, 4000), (3000, 2000), (2, 3000)].enumerated() {
            write(d.appendingPathComponent("shape\(i).jpg"), w: s.0, h: s.1, seed: 30 + i, shot: day(9, i * 40))
        }
    } }
    /// File dates say "today" (copied), EXIF says morning and evening: must group by shot time (R-16).
    static var exifDay: URL { folder("Day") { d in
        let now = Date(), cam = (make: "Canon", model: "Canon EOS R6")
        write(d.appendingPathComponent("m1.jpg"), seed: 71, shot: day(9, 0, 0), camera: cam, modified: now)
        write(d.appendingPathComponent("m2.jpg"), seed: 72, shot: day(9, 0, 20), camera: cam, modified: now)
        write(d.appendingPathComponent("e1.jpg"), seed: 73, shot: day(18, 30, 0), camera: cam, modified: now)
        write(d.appendingPathComponent("e2.jpg"), seed: 74, shot: day(18, 30, 15), camera: cam, modified: now)
    } }
    /// Portrait shot with the phone turned: pixels landscape, EXIF orientation 6 (R-1D).
    static var rotated: URL { folder("Phone") { d in write(d.appendingPathComponent("portrait.jpg"), w: 640, h: 420, seed: 91, shot: day(12), orientation: 6) } }
    static func batch(_ name: String, _ n: Int, startHour: Int = 9) -> URL { folder(name) { d in
        for i in 0..<n { write(d.appendingPathComponent("\(name)-\(i).jpg"), w: 900, h: 600, seed: i, shot: day(startHour, (i * 3) / 60, (i * 3) % 60)) }
    } }
    /// 40 photos per scene, every 5th a 1s burst frame. (R-85)
    static func big(_ n: Int) -> URL { folder("Big folder \(n)") { d in
        for i in 0..<n {
            let scene = i / 40, t = Fixtures.day(7).addingTimeInterval(Double(scene * 3600 + (i % 40) * (i % 5 == 0 ? 1 : 9)))
            write(d.appendingPathComponent(String(format: "DSC%05d.JPG", 10000 + i)), w: i % 3 == 0 ? 600 : 900, h: i % 3 == 0 ? 900 : 600, seed: i, shot: t)
        }
    } }
    static var raws: URL { folder("Raws") { d in for n in ["A.CR2", "B.NEF", "C.ARW", "D.dng"] { bytes(d.appendingPathComponent(n), 5000) } } }
}
