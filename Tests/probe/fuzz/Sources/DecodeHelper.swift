import CoreImage
import Darwin
import Foundation
import ImageIO

/// `hostile-decode`: Apple's decoders on mutated input, in a process of its own, signed with the
/// app's sandbox entitlements (`Config/Lumina-Sets.entitlements`) by `run.sh`. A decoder that
/// crashes takes this helper down, nothing else; the driver (`fuzz.mjs decode`) keeps the input and
/// the crash report and starts the helper again after that case.
///
/// It opens no file: each case arrives on stdin as one JSON line `{"i", "kind": "jpeg"|"raw", "len"}`
/// followed by `len` bytes. One JSON line per case on stdout. A JPEG goes through what the app does
/// with an embedded preview (`SetsIngest.thumbnail` and `.upright`, the app's code, unchanged) and a
/// plain full decode; an ARW through `CIRAWFilter` (default decoder) rendered at 1/8 scale, as the
/// decoder probe's proof render does. Footprint over 1.5 GB: a `memory` line and exit 4.
@main
enum DecodeHelper {
    final class Box: @unchecked Sendable { var current = "-" }
    static var buf = [UInt8]()
    static var pos = 0

    static func fill() -> Bool {
        var chunk = [UInt8](repeating: 0, count: 1 << 20)
        let n = read(0, &chunk, chunk.count)
        guard n > 0 else { return false }
        if pos > 0 { buf.removeFirst(pos); pos = 0 }
        buf.append(contentsOf: chunk[0 ..< n])
        return true
    }

    static func line() -> String? {
        while true {
            if let k = buf[pos...].firstIndex(of: 10) { let s = String(decoding: buf[pos ..< k], as: UTF8.self); pos = k + 1; return s }
            guard fill() else { return nil }
        }
    }

    static func bytes(_ n: Int) -> Data? {
        while buf.count - pos < n { guard fill() else { return nil } }
        let d = Data(buf[pos ..< pos + n]); pos += n
        return d
    }

    static func main() {
        let box = Box()
        Fuzz.memoryWatchdog(limit: 1536 << 20) { box.current }
        sandboxCheck()
        let ctx = CIContext(options: [.cacheIntermediates: false])
        while let header = line() {
            guard let h = (try? JSONSerialization.jsonObject(with: Data(header.utf8))) as? [String: Any], let i = h["i"] as? Int, let len = h["len"] as? Int, let kind = h["kind"] as? String,
                  let data = bytes(len) else { break }
            box.current = "\(i)"
            Fuzz.emit(["event": "start", "i": i])
            let t0 = Date()
            var o: [String: Any] = ["event": "case", "i": i, "kind": kind]
            autoreleasepool {
                if kind == "jpeg" { jpeg(data, &o) } else { raw(data, ctx, &o) }
            }
            o["ms"] = Int(Date().timeIntervalSince(t0) * 1000)
            o["fpMB"] = Fuzz.footprint() >> 20
            Fuzz.emit(o)
        }
        Fuzz.emit(["event": "end"])
    }

    /// Whether the sandbox holds: a sandboxed helper has a container and cannot list the real home.
    static func sandboxCheck() {
        let home = String(cString: getpwuid(getuid()).pointee.pw_dir)
        let listed = (try? FileManager.default.contentsOfDirectory(atPath: home + "/LuminaEvidence")) != nil
        let docs = (try? FileManager.default.contentsOfDirectory(atPath: home + "/Documents")) != nil
        Fuzz.emit(["event": "sandbox", "container": ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? NSNull(),
                   "homeDir": NSHomeDirectory(), "realHomeListable": listed, "documentsListable": docs])
    }

    static func jpeg(_ d: Data, _ o: inout [String: Any]) {
        let thumb = SetsIngest.thumbnail(jpeg: d, orientation: 6)
        let up = SetsIngest.upright(jpeg: d, orientation: 3, quality: 0.92)
        var full = false
        if let s = CGImageSourceCreateWithData(d as CFData, [kCGImageSourceShouldCache: false] as CFDictionary), CGImageSourceGetCount(s) > 0,
           let img = CGImageSourceCreateImageAtIndex(s, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            full = img.width > 0
            o["w"] = img.width; o["h"] = img.height
        }
        o["thumb"] = thumb?.count ?? 0
        o["upright"] = up?.count ?? 0
        o["ok"] = full
    }

    static func raw(_ d: Data, _ ctx: CIContext, _ o: inout [String: Any]) {
        guard let f = CIRAWFilter(imageData: d, identifierHint: "com.sony.arw-raw-image") else { o["ok"] = false; o["why"] = "no filter"; return }
        o["versions"] = f.supportedDecoderVersions.map(\.rawValue)
        f.scaleFactor = 0.125
        guard let img = f.outputImage, img.extent.width.isFinite, img.extent.width > 0 else { o["ok"] = false; o["why"] = "no image"; return }
        let r = img.extent.integral
        guard r.width * r.height < 40_000_000 else { o["ok"] = false; o["why"] = "extent \(r.width)x\(r.height)"; return }
        let cg = ctx.createCGImage(img, from: r)
        o["ok"] = cg != nil
        o["w"] = cg?.width ?? 0; o["h"] = cg?.height ?? 0
    }
}
