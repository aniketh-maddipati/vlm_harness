import CoreImage
import CryptoKit
import Foundation

/// A disk cache of developed RAWs for `lumina-render batch --cache <dir>`: the rawDevelop stage's
/// output (half-float RGBA in the working space, exactly what `LookPipeline.rasterised` keeps in
/// memory) plus its as-shot white balance, so a parity run that only changed the look stages
/// (rules-v1.json coefficients, a kernel) re-runs them on a bitmap instead of decoding every RAW
/// again. The tool only; the app has its own caches (`LookRenderer`, `LookBases`).
///
/// Key: the file (path, size, modification time), the develop size, the decoder version, `nr`,
/// the rawDevelop coefficients, the working space and the macOS version (the decoders ship with
/// the OS). Anything else that changes the develop (a change to `LookPipeline.develop` itself)
/// needs `--no-cache` or a bump of `version`.
struct DevelopCache {
    static let version = 1
    let dir: URL

    init(dir: URL) throws {
        self.dir = dir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func key(image: String, px: Int, decoder: Int?, nr: Double?, rules: LookRules) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: image)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? -1
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let raw = (rules.stages["rawDevelop"]?.coefficients ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        let text = ["v\(version)", URL(fileURLWithPath: image).standardizedFileURL.path, "\(size)", "\(mtime)", "\(px)", "\(decoder ?? 0)",
                    nr.map { "\($0)" } ?? "-", raw, rules.workingSpace, ProcessInfo.processInfo.operatingSystemVersionString].joined(separator: "|")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func paths(_ key: String) -> (bin: URL, meta: URL) {
        (dir.appendingPathComponent(key + ".rgbah"), dir.appendingPathComponent(key + ".json"))
    }

    /// The cached develop, or nil (missing, or written by a different layout).
    func load(_ key: String, workingSpace: CGColorSpace) -> LookPipeline.Developed? {
        let p = paths(key)
        guard let metaData = try? Data(contentsOf: p.meta),
              let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              let w = meta["width"] as? Int, let h = meta["height"] as? Int, let rowBytes = meta["rowBytes"] as? Int,
              let kelvin = meta["kelvin"] as? Double, let tint = meta["tint"] as? Double,
              let bytes = try? Data(contentsOf: p.bin, options: .alwaysMapped), bytes.count == rowBytes * h else { return nil }
        // Mark the entry used: the caller prunes what a run did not touch (`prune_develop_cache`).
        let now: [FileAttributeKey: Any] = [.modificationDate: Date()]
        try? FileManager.default.setAttributes(now, ofItemAtPath: p.meta.path)
        try? FileManager.default.setAttributes(now, ofItemAtPath: p.bin.path)
        let img = CIImage(bitmapData: bytes, bytesPerRow: rowBytes, size: CGSize(width: w, height: h), format: .RGBAh, colorSpace: workingSpace)
        return LookPipeline.Developed(image: img, asShot: Look.WhiteBalance(kelvin: kelvin, tint: tint))
    }

    /// Writes the bitmap first and the metadata last, so a half-written entry is never read.
    func store(_ key: String, bitmap: Data, width: Int, height: Int, rowBytes: Int, asShot: Look.WhiteBalance) {
        let p = paths(key)
        do {
            try bitmap.write(to: p.bin, options: .atomic)
            let meta: [String: Any] = ["width": width, "height": height, "rowBytes": rowBytes, "kelvin": asShot.kelvin, "tint": asShot.tint, "version": Self.version]
            try JSONSerialization.data(withJSONObject: meta).write(to: p.meta, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("lumina-render: develop cache write failed: \(error)\n".utf8))
        }
    }
}

extension LookPipeline {
    /// The developed image rendered once into half floats in the working space (what
    /// `rasterised` does), returned as bytes too so the develop cache can keep them.
    func rasterisedBitmap(_ dev: Developed) throws -> (Developed, Data, Int, Int, Int) {
        let e = dev.extent.integral
        let w = Int(e.width), h = Int(e.height), rowBytes = w * 8
        guard w > 0, h > 0 else { throw Failure("empty develop") }
        var data = Data(count: rowBytes * h)
        data.withUnsafeMutableBytes { buf in
            context.render(dev.image, toBitmap: buf.baseAddress!, rowBytes: rowBytes, bounds: e, format: .RGBAh, colorSpace: workingSpace)
        }
        let img = CIImage(bitmapData: data, bytesPerRow: rowBytes, size: CGSize(width: w, height: h), format: .RGBAh, colorSpace: workingSpace)
        return (Developed(image: img, asShot: dev.asShot), data, w, h, rowBytes)
    }
}
