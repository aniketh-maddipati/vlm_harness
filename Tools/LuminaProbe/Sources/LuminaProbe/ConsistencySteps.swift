import AppKit
import CoreImage
import ImageIO

/// Canvas vs export consistency (`probe.sh consistency`): is the picture on the Edit canvas the
/// picture that gets exported? `editParity` compares the two at the same size, with the same
/// decoder, for one look. This step compares what the canvas shows (the canvas tier's decoder,
/// developed at canvas size, the look applied to the cached base) with what Export writes (the
/// pinned decoder at full size through `SetsLookExport`), scaled down to the canvas, for every
/// stage of the look on several photos. Per photo and look, ΔE2000 for four pairs:
///
/// - `full`:     canvas vs the full-size export scaled to the canvas (what the user would notice);
/// - `sameSize`: canvas vs an export rendered at canvas size (the control `editParity` runs);
/// - `decoder`:  a canvas developed with the previous decoder version vs the full-size export with
///               the newest (what a canvas on RAW 8 and an export on RAW 9 would cost), on the
///               neutral look and the combos only;
/// - `drag`:     the quarter-size drag preview scaled up vs the canvas at rest (how much the
///               picture changes when the thumb is released).
@MainActor
enum ConsistencySteps {
    /// Every stage alone at a moderate and a strong value, geometry, and two realistic combos.
    static let defaultLooks: [(name: String, look: String)] = [
        ("neutral", ""),
        ("ev +1", "ev:+1.00"), ("ev -1", "ev:-1.00"),
        ("wb warm", "wb:7500/+10"), ("wb cool", "wb:3800/-10"),
        ("contrast +40", "con:+40"), ("contrast -40", "con:-40"),
        ("highlights -60", "hl:-60"), ("highlights +40", "hl:+40"),
        ("shadows +60", "sh:+60"), ("shadows -40", "sh:-40"),
        ("whites +40", "wh:+40"), ("blacks -40", "bl:-40"), ("blacks +40", "bl:+40"),
        ("vibrance +50", "vib:+50"), ("saturation +40", "sat:+40"), ("saturation -40", "sat:-40"),
        ("clarity +50", "clr:+50"), ("clarity -50", "clr:-50"),
        ("sharpen 80", "shp:80"), ("sharpen 150", "shp:150"),
        ("vignette -50", "vig:-50"), ("vignette +50", "vig:+50"),
        ("noise reduction 50", "nr:50"),
        ("black and white", "bw:1"),
        ("crop", "crop:0.1,0.1,0.6,0.6"), ("crop + straighten", "crop:0.1,0.1,0.8,0.8/3"),
        ("combo portrait", "ev:+0.70 con:+20 hl:-40 sh:+30 clr:+20 shp:60 vig:-20"),
        ("combo evening", "ev:-0.50 wb:6500/+5 con:+10 wh:+20 bl:-10 vib:+20 nr:30"),
    ]

    struct Row: Encodable { let photo: String; let look: String; let pair: String; let median: Double; let mean: Double; let p95: Double; let max: Double; let pixels: Int }

    static func run(host: ProbeHost, _ s: [String: Any], folder: URL, outDir: URL) async throws -> EditSteps.Outcome {
        guard let bridge = host.bridge, let canvas = bridge.canvas else { throw ProbeError("editConsistency needs app mode") }
        let fm = FileManager.default
        let all = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "arw" && !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !all.isEmpty else { throw ProbeError("no ARWs in \(folder.path)") }
        // Distinct photos only (fixture folders repeat a few files under many names: same size, same
        // bytes), spread over the folder so they differ in light and lens.
        var sizes: Set<Int> = []
        let distinct = all.filter { sizes.insert((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0).inserted }
        let count = min(distinct.count, s["count"] as? Int ?? 12)
        let raws = (0..<count).map { distinct[min(distinct.count - 1, $0 * distinct.count / count + distinct.count / (2 * count))] }
        let size = (s["canvas"] as? [Double]).flatMap { $0.count == 2 ? CGSize(width: $0[0], height: $0[1]) : nil } ?? CGSize(width: 1760, height: 1280)
        let step = max(1, s["sampleStep"] as? Int ?? 2)
        let looks: [(name: String, look: String)] = (s["looks"] as? [[String: String]])?.compactMap { d in d["look"].map { (d["name"] ?? $0, $0) } } ?? defaultLooks
        let pipe = canvas.pipeline
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        var o = EditSteps.Outcome(note: "")
        guard !LookPipeline.supportedDecoderVersions(url: raws[0]).isEmpty else {
            o.note = "\(raws[0].lastPathComponent) is not a RAW Core Image reads (synthetic fixture?): consistency needs real ARWs"
            return o
        }
        var rows: [Row] = []
        var decoders: [String: [String: Int]] = [:]
        let bases = LookBases(pipeline: pipe, byteCap: 800 << 20, maxPhotos: 2)
        var info: [String: LookDecoderInfo] = [:]          // per body, measured once

        func cg(_ img: CIImage) -> CGImage? { pipe.context.createCGImage(pipe.clamped(img), from: img.extent.integral, format: .RGBA8, colorSpace: srgb) }
        func decode(_ data: Data) -> CGImage? { CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } }
        /// An export scaled to the canvas picture's size with the pipeline's own Lanczos.
        func scaled(_ full: CGImage, to target: CGImage) -> CGImage? {
            let img = LookPipeline.scaled(LookPipeline.atOrigin(CIImage(cgImage: full)), longEdge: max(target.width, target.height))
            return pipe.context.createCGImage(img, from: img.extent.integral, format: .RGBA8, colorSpace: srgb)
        }

        for url in raws {
            let name = url.lastPathComponent, rel = folder.lastPathComponent + "/" + name
            let model = cameraModel(url) ?? "?"
            if info[model] == nil { info[model] = LookDecoderProbe.probe(url: url, rules: pipe.rules) }
            let body = info[model]!
            let pinned = body.newest
            let canvasDecoder = LookRawPolicy.version(for: .canvas, body: body, pinned: pinned)
            let exportDecoder = LookRawPolicy.version(for: .export, body: body, pinned: pinned)
            let older = pinned.flatMap { LookRawPolicy.fallback(after: $0, supported: body.supported) }
            decoders[name] = ["canvas": canvasDecoder ?? 0, "export": exportDecoder ?? 0, "older": older ?? 0]
            for (lookName, text) in looks {
                do {
                    let look = try Look.parse(text)
                    let key = LookBases.Key(rel: rel, decoder: canvasDecoder, look: look, canvas: size)
                    let e = try bases.build(key, url: url, look: look, preview: nil)
                    guard let shown = cg(pipe.apply(look, to: LookPipeline.Developed(image: e.base, asShot: e.asShot), crop: false)) else { throw ProbeError("canvas render failed") }
                    func add(_ pair: String, _ other: CGImage?) {
                        guard let other else { o.failures.append("editConsistency: \(name) · \(lookName) · \(pair): render failed"); return }
                        if abs(shown.width - other.width) > 2 || abs(shown.height - other.height) > 2 {
                            o.failures.append("editConsistency: \(name) · \(lookName) · \(pair): sizes differ \(shown.width)×\(shown.height) vs \(other.width)×\(other.height)")
                        }
                        let de = stats(shown, other, step: step)
                        rows.append(Row(photo: name, look: lookName, pair: pair, median: de.median, mean: de.mean, p95: de.p95, max: de.max, pixels: de.pixels))
                    }
                    // What Export writes: the pinned decoder at full size, scaled to the canvas picture.
                    let (fullData, _) = try SetsLookExport.render(raw: url, look: text, px: nil, format: "png", decoder: exportDecoder)
                    let full = decode(fullData)
                    add("full", full.flatMap { scaled($0, to: shown) })
                    // The control: the export graph at the canvas picture's size, the canvas's decoder.
                    // (Not for a crop: the export's `px` is the uncropped long edge, so the sizes can't be made equal.)
                    if look.crop == nil {
                        let (sameData, _) = try SetsLookExport.render(raw: url, look: text, px: max(shown.width, shown.height), format: "png", decoder: canvasDecoder)
                        add("sameSize", decode(sameData))
                    }
                    // The drag preview (a quarter on each edge), shown stretched over the canvas.
                    if let small = cg(pipe.apply(look, to: LookPipeline.Developed(image: e.small, asShot: e.asShot), crop: false)) {
                        let up = CIImage(cgImage: small).transformed(by: CGAffineTransform(scaleX: CGFloat(shown.width) / CGFloat(small.width), y: CGFloat(shown.height) / CGFloat(small.height)))
                        add("drag", pipe.context.createCGImage(up, from: CGRect(x: 0, y: 0, width: shown.width, height: shown.height), format: .RGBA8, colorSpace: srgb))
                    }
                    // A canvas one decoder version behind the export (RAW 8 canvas, RAW 9 export, rehearsed with what this Mac has).
                    if let older, older != exportDecoder, lookName == "neutral" || lookName.hasPrefix("combo"), let full {
                        let k2 = LookBases.Key(rel: rel, decoder: older, look: look, canvas: size)
                        let e2 = try bases.build(k2, url: url, look: look, preview: nil)
                        if let behind = cg(pipe.apply(look, to: LookPipeline.Developed(image: e2.base, asShot: e2.asShot), crop: false)), let exp = scaled(full, to: behind) {
                            let de = stats(behind, exp, step: step)
                            rows.append(Row(photo: name, look: lookName, pair: "decoder", median: de.median, mean: de.mean, p95: de.p95, max: de.max, pixels: de.pixels))
                        }
                    }
                } catch {
                    o.failures.append("editConsistency: \(name) · \(lookName): \(error)")
                }
            }
            bases.forget(rel: rel)
            await Task.yield()
        }

        // Per look and pair: the median over photos of the per-photo median and p95, and the worst photo.
        func agg(_ r: [Row]) -> [String: Double] {
            let m = r.map(\.median).sorted(), p = r.map(\.p95).sorted()
            guard !m.isEmpty else { return [:] }
            return ["median": m[m.count / 2], "worstMedian": m.last!, "p95": p[p.count / 2], "worstP95": p.last!, "photos": Double(m.count)]
        }
        var summary: [[String: Any]] = []
        for (lookName, text) in looks {
            var entry: [String: Any] = ["look": lookName, "string": text]
            for pair in ["full", "sameSize", "drag", "decoder"] {
                let a = agg(rows.filter { $0.look == lookName && $0.pair == pair })
                if !a.isEmpty { entry[pair] = a }
            }
            summary.append(entry)
        }
        let overall = Dictionary(uniqueKeysWithValues: ["full", "sameSize", "drag", "decoder"].map { pair in (pair, agg(rows.filter { $0.pair == pair })) })
        let report: [String: Any] = ["folder": folder.path, "photos": raws.map(\.lastPathComponent), "canvas": [Int(size.width), Int(size.height)], "sampleStep": step,
                                     "decoders": decoders, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                     "summary": summary, "overall": overall,
                                     "rows": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(rows))) ?? []]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: outDir.appendingPathComponent("consistency.json"))

        // Gates, when the scenario sets them: the worst photo of any look, canvas vs full-size export.
        let full = rows.filter { $0.pair == "full" }
        if EditSteps.gate, let cap = s["maxMedianDE"] as? Double {
            for r in full where r.median > cap { o.failures.append(String(format: "editConsistency: %@ · %@: ΔE median %.2f > %.2f", r.photo, r.look, r.median, cap)) }
        }
        if EditSteps.gate, let cap = s["maxP95DE"] as? Double {
            for r in full where r.p95 > cap { o.failures.append(String(format: "editConsistency: %@ · %@: ΔE p95 %.2f > %.2f", r.photo, r.look, r.p95, cap)) }
        }
        var lines = [String(format: "%d photos × %d looks at %d×%d · decoders %@", raws.count, looks.count, Int(size.width), Int(size.height),
                            Set(decoders.values.map { "canvas raw \($0["canvas"] ?? 0), export raw \($0["export"] ?? 0)" }).sorted().joined(separator: "; "))]
        for pair in ["full", "sameSize", "drag", "decoder"] {
            if let a = overall[pair], !a.isEmpty {
                lines.append(String(format: "%@: ΔE median %.2f (worst photo·look %.2f) · p95 %.2f (worst %.2f)", pair, a["median"]!, a["worstMedian"]!, a["p95"]!, a["worstP95"]!))
            }
        }
        let worst = summary.compactMap { e -> (String, Double, Double)? in
            guard let f = e["full"] as? [String: Double] else { return nil }
            return (e["look"] as? String ?? "", f["median"] ?? 0, f["p95"] ?? 0)
        }.sorted { $0.2 > $1.2 }.prefix(6)
        lines.append("largest canvas-vs-export differences (median over photos): " + worst.map { String(format: "%@ %.2f / p95 %.2f", $0.0, $0.1, $0.2) }.joined(separator: " · "))
        o.note = "\n  " + lines.joined(separator: "\n  ")
        return o
    }

    /// The body, from the file's TIFF tags: the decoder map is per body.
    static func cameraModel(_ url: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] else { return nil }
        return tiff[kCGImagePropertyTIFFModel] as? String
    }

    /// CIEDE2000 over the common area on a grid of every `step`-th pixel (the full grid at step 1).
    static func stats(_ a: CGImage, _ b: CGImage, step: Int) -> LookParity.DE {
        let w = min(a.width, b.width), h = min(a.height, b.height)
        guard w > 0, h > 0, let ca = a.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)), let cb = b.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)) else {
            return LookParity.DE(mean: 100, median: 100, p95: 100, max: 100, pixels: 0)
        }
        let pa = Pixels.rgba(ca), pb = Pixels.rgba(cb)
        var d: [Double] = []
        d.reserveCapacity((w / step + 1) * (h / step + 1))
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                let i = (y * w + x) * 4
                if i + 3 < pa.count, i + 3 < pb.count {
                    d.append(LookParity.de2000(LookParity.lab(pa[i], pa[i + 1], pa[i + 2]), LookParity.lab(pb[i], pb[i + 1], pb[i + 2])))
                }
                x += step
            }
            y += step
        }
        guard !d.isEmpty else { return LookParity.DE(mean: 100, median: 100, p95: 100, max: 100, pixels: 0) }
        d.sort()
        return LookParity.DE(mean: d.reduce(0, +) / Double(d.count), median: d[d.count / 2], p95: d[Int(Double(d.count - 1) * 0.95)], max: d.last ?? 0, pixels: d.count)
    }
}
