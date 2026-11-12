import CoreImage
import Foundation

let usage = """
lumina-render — render an ARW through the app's LookPipeline (Tools/parity)

  lumina-render render <image> [--look "<look string>"] [--px 2048] [--space prophoto|srgb|p3]
                       [--out file.tif|.jpg|.png] [--rules rules-v1.json] [--decoder 8] [--json]
      One render. A 16-bit TIFF unless --out ends in .jpg / .png. Prints develop and render
      times (and JSON with --json). <image> may be any RAW Core Image reads, or a JPEG/TIFF/PNG.
      --decoder picks a RAW decoder version (RAW 9: `make parity DECODER=9`, once per version present).

  lumina-render batch <jobs.json> [--rules rules-v1.json] [--decoder 8] [--cache dir | --no-cache]
      Many renders, one process: [{"image", "look", "px", "out", "space", "decoder"?}]. Each
      (image, px, decoder) is developed once. Prints one JSON line per job with timings; exit 1 if any job failed.
      --cache (or $LUMINA_RENDER_CACHE) keeps each develop on disk across runs, keyed by file, size,
      decoder, nr, the rawDevelop coefficients and the macOS version; each line's "develop" says
      decode / disk / memory.

  lumina-render asshot <image>...
      As-shot white balance, upright size and EXIF orientation from the RAW's metadata, no decode.

  lumina-render info <image>
      As-shot white balance, native size, develop time, the RAW decoder versions this Mac offers.

  lumina-render ramp [--look "<look string>"] [--rules rules-v1.json] [--out ramp.json]
      The graph on flat patches (a grey ramp and test colours) next to LookMath's scalar chain,
      as JSON, for Tools/parity/lookmath.py --check: proves the Metal, Swift and numpy copies of
      the stage maths agree.

  lumina-render sky <image> [--px 2048] [--out mask.png] [--no-gate] [--rules …]
      The sky mask as the app finds it (Vision's scene gate, then LookMasks.sky on a ≤1024 px sRGB
      base render), as an 8-bit PNG, plus JSON (gate score, area). LookSky's prototype.

  render / batch take --sky (batch: "sky": true per job): the sky mask is found and attached, so
  `mask:sky/…` adjustments render (without it every mask: token is left out, as before). With
  LUMINA_SKY=1, `blu` (sky blue) is a key inside a mask.

Rules: --rules, else $LUMINA_RULES, else Lumina/Sets/Look/rules-v1.json found from this checkout.
"""

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i); return true
}
func fail(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("lumina-render: " + msg + "\n").utf8)); exit(code)
}

/// Rules from --rules, $LUMINA_RULES, or the checkout this tool was built from.
func loadRules(_ path: String?) throws -> LookRules {
    if let path { return try LookRules.load(from: URL(fileURLWithPath: path)) }
    if let env = ProcessInfo.processInfo.environment["LUMINA_RULES"], !env.isEmpty { return try LookRules.load(from: URL(fileURLWithPath: env)) }
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<8 {
        let c = dir.appendingPathComponent("Lumina/Sets/Look/rules-v1.json")
        if FileManager.default.fileExists(atPath: c.path) { return try LookRules.load(from: c) }
        dir.deleteLastPathComponent()
    }
    fail("no rules file: pass --rules or set LUMINA_RULES")
}

func ms(_ t: Date) -> Int { Int(Date().timeIntervalSince(t) * 1000) }

func encode(_ pipe: LookPipeline, _ img: CIImage, to out: URL, space: LookPipeline.OutputSpace) throws -> Data {
    let data: Data
    switch out.pathExtension.lowercased() {
    case "jpg", "jpeg": data = try pipe.jpeg(img, quality: 0.92, space: space)
    case "png": data = try pipe.png(img, space: space)
    default: data = try pipe.tiff16(img, space: space)
    }
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: out, options: .atomic)
    return data
}

func json(_ obj: Any) -> String {
    String(data: (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? "{}"
}

guard let command = args.first else { print(usage); exit(2) }
args.removeFirst()

do {
    switch command {
    case "render":
        let lookText = option("--look") ?? "", px = Int(option("--px") ?? "2048") ?? 2048
        let space = LookPipeline.OutputSpace(rawValue: option("--space") ?? "prophoto") ?? .prophoto
        let outPath = option("--out"), rulesPath = option("--rules"), wantJSON = flag("--json")
        let decoder = option("--decoder").flatMap(Int.init), wantSky = flag("--sky")
        guard let imagePath = args.first else { fail(usage, code: 2) }
        let rules = try loadRules(rulesPath)
        let pipe = try LookPipeline(rules: rules)
        let look = try Look.parse(lookText)
        let t0 = Date()
        let dev = try LookPipeline.developAny(url: URL(fileURLWithPath: imagePath), longEdge: px, rules: rules, decoderVersion: decoder, nr: look.nr)
        var (raster, bytes) = try pipe.rasterised(dev)
        let developMs = ms(t0)
        let t1 = Date()
        if wantSky { let found = try SkyMask.find(pipe, raster).found; raster = raster.withMasks(found, key: LookPipeline.PhotoMasks.key(rel: imagePath, found)) }
        let img = pipe.apply(look, to: raster)
        let out = URL(fileURLWithPath: outPath ?? ((imagePath as NSString).deletingPathExtension + ".lumina.tif"))
        let data = try encode(pipe, img, to: out, space: space)
        let renderMs = ms(t1)
        let info: [String: Any] = ["image": imagePath, "out": out.path, "look": look.format(), "px": px, "space": space.rawValue,
                                   "width": Int(img.extent.width), "height": Int(img.extent.height), "bytes": data.count, "rasterBytes": bytes,
                                   "asShot": ["kelvin": dev.asShot.kelvin, "tint": dev.asShot.tint], "developMs": developMs, "renderMs": renderMs,
                                   "decoder": decoder ?? 0]
        if wantJSON { print(json(info)) }
        else { print("\(out.lastPathComponent): \(Int(img.extent.width))×\(Int(img.extent.height)) \(space.rawValue) · develop \(developMs) ms · render+encode \(renderMs) ms · as shot \(Int(dev.asShot.kelvin)) K \(Int(dev.asShot.tint))") }

    case "batch":
        let rulesPath = option("--rules")
        let decoderAll = option("--decoder").flatMap(Int.init)
        let cacheDir = option("--cache") ?? ProcessInfo.processInfo.environment["LUMINA_RENDER_CACHE"]
        let noCache = flag("--no-cache")
        guard let plan = args.first, let data = FileManager.default.contents(atPath: plan),
              let jobs = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { fail("batch wants a JSON array of jobs", code: 2) }
        let rules = try loadRules(rulesPath)
        let pipe = try LookPipeline(rules: rules)
        let disk = try (noCache ? nil : cacheDir).flatMap { try DevelopCache(dir: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) }
        var developed: [String: LookPipeline.Developed] = [:]
        var skies: [String: [LookMasks.Found]] = [:]
        var failed = 0
        for job in jobs {
            let image = job["image"] as? String ?? "", lookText = job["look"] as? String ?? "", px = job["px"] as? Int ?? 2048
            let space = LookPipeline.OutputSpace(rawValue: job["space"] as? String ?? "prophoto") ?? .prophoto
            let out = job["out"] as? String ?? ((image as NSString).deletingPathExtension + ".lumina.tif")
            let decoder = (job["decoder"] as? Int) ?? decoderAll
            var line: [String: Any] = ["image": image, "look": lookText, "px": px, "out": out, "decoder": decoder ?? 0]
            do {
                let parsedLook = try Look.parse(lookText)
                let key = "\(image)|\(px)|\(decoder ?? 0)|\(parsedLook.nr ?? -1)"
                var developMs = 0, source = "memory"
                if developed[key] == nil {
                    let t0 = Date()
                    let diskKey = disk.map { _ in DevelopCache.key(image: image, px: px, decoder: decoder, nr: parsedLook.nr, rules: rules) }
                    if let disk, let diskKey, let hit = disk.load(diskKey, workingSpace: pipe.workingSpace) {
                        developed[key] = hit
                        source = "disk"
                    } else {
                        let dev = try LookPipeline.developAny(url: URL(fileURLWithPath: image), longEdge: px, rules: rules, decoderVersion: decoder, nr: parsedLook.nr)
                        let (raster, bytes, w, h, rowBytes) = try pipe.rasterisedBitmap(dev)
                        developed[key] = raster
                        if let disk, let diskKey { disk.store(diskKey, bitmap: bytes, width: w, height: h, rowBytes: rowBytes, asShot: dev.asShot, anchor: dev.anchor, style: dev.style) }
                        source = "decode"
                    }
                    developMs = ms(t0)
                    // One developed image per size at a time: the sweep walks image by image.
                    if developed.count > 2 { for k in developed.keys where k != key { developed[k] = nil } }
                }
                var dev = developed[key]!
                if job["sky"] as? Bool == true {
                    if skies[key] == nil { skies = [key: try SkyMask.find(pipe, dev).found] }
                    let found = skies[key]!
                    dev = dev.withMasks(found, key: LookPipeline.PhotoMasks.key(rel: key, found))
                    line["sky"] = !found.isEmpty
                }
                let t1 = Date()
                let img = pipe.apply(parsedLook, to: dev)
                _ = try encode(pipe, img, to: URL(fileURLWithPath: out), space: space)
                line["ok"] = true; line["developMs"] = developMs; line["renderMs"] = ms(t1); line["develop"] = source
                line["asShot"] = ["kelvin": dev.asShot.kelvin, "tint": dev.asShot.tint]
                line["width"] = Int(img.extent.width); line["height"] = Int(img.extent.height)
            } catch {
                failed += 1
                line["ok"] = false; line["error"] = "\(error)"
            }
            print(json(line))
            fflush(stdout)
        }
        exit(failed == 0 ? 0 : 1)

    case "sky":
        let px = Int(option("--px") ?? "2048") ?? 2048, outPath = option("--out"), noGate = flag("--no-gate")
        let rules = try loadRules(option("--rules"))
        guard let imagePath = args.first else { fail(usage, code: 2) }
        let pipe = try LookPipeline(rules: rules)
        let dev = try LookPipeline.developAny(url: URL(fileURLWithPath: imagePath), longEdge: px, rules: rules)
        let t0 = Date()
        let r = try SkyMask.find(pipe, try pipe.rasterised(dev).0, gate: !noGate)
        if let outPath, let p = r.plane { try SkyMask.writePNG(p, to: URL(fileURLWithPath: outPath)) }
        let area = r.plane.map { p in Double(p.values.reduce(0, +)) / Double(max(1, p.values.count)) } ?? 0
        let top = r.labels.sorted { $0.value > $1.value }.prefix(5).map { ["label": $0.key, "p": Double($0.value)] }
        print(json(["image": imagePath, "gate": r.gate.map(Double.init) as Any, "area": area, "found": !r.found.isEmpty,
                    "width": r.plane?.width ?? 0, "height": r.plane?.height ?? 0, "ms": ms(t0), "labels": top, "out": outPath as Any]))

    case "diagnose":
        // LookSky's F1 (clip diagnosis), F2 (meter) and F6 (capture tip) on one photo, as JSON.
        let px = Int(option("--px") ?? "1024") ?? 1024, outDir = option("--out-dir"), noGate = flag("--no-gate")
        let target = option("--target").flatMap(Double.init) ?? LookSky.targetL
        let rules = try loadRules(option("--rules"))
        guard let imagePath = args.first else { fail(usage, code: 2) }
        let url = URL(fileURLWithPath: imagePath)
        let pipe = try LookPipeline(rules: rules)
        let t0 = Date()
        let dev = try pipe.rasterised(try LookPipeline.developAny(url: url, longEdge: px, rules: rules)).0
        let sky = try SkyMask.find(pipe, dev, gate: !noGate)
        let tSky = ms(t0)
        let t1 = Date()
        let maps = LookSkyClip.maps(url: url, longEdge: 512, boost: rules.k("rawDevelop", "boostAmount", 1))
        let tClip = ms(t1)
        // the develop's luma at ≤ 512 px, row 0 at the top
        let small = dev.image.transformed(by: CGAffineTransform(scaleX: min(1, 512 / dev.longEdge), y: min(1, 512 / dev.longEdge)))
        let e = small.extent.integral, w = Int(e.width), h = Int(e.height)
        var buf = [Float](repeating: 0, count: 4 * w * h)
        pipe.context.render(small, toBitmap: &buf, rowBytes: 16 * w, bounds: e, format: .RGBAf, colorSpace: pipe.workingSpace)
        var luma = LookMasks.Plane(width: w, height: h)
        for i in 0..<(w * h) { luma.values[i] = Float(rules.luma[0]) * buf[4 * i] + Float(rules.luma[1]) * buf[4 * i + 1] + Float(rules.luma[2]) * buf[4 * i + 2] }
        let meter = LookSky.meter(luma: luma, sky: sky.plane, rules: rules, target: target)
        var out: [String: Any] = ["image": imagePath, "gate": sky.gate.map(Double.init) as Any, "skyMs": tSky, "clipMs": tClip,
                                  "recoverySwitch": maps?.clipped != nil]
        if let maps {
            let d = LookSky.diagnose(sky: sky.plane, white: maps.white, clipped: maps.clipped)
            let stops = sky.plane.flatMap { LookSkyClip.stopsOver(sky: $0, maps: maps) }
            out["verdict"] = d.verdict.rawValue; out["sky"] = d.sky; out["white"] = d.white; out["clipped"] = d.clipped as Any
            out["stopsOver"] = stops as Any; out["tip"] = LookSky.captureTip(d, stopsOver: stops) as Any
            if let outDir {
                let dir = URL(fileURLWithPath: outDir)
                try SkyMask.writePNG(maps.white, to: dir.appendingPathComponent("white.png"))
                if let c = maps.clipped { try SkyMask.writePNG(c, to: dir.appendingPathComponent("clipped.png")) }
            }
        }
        if let outDir, let p = sky.plane { try SkyMask.writePNG(p, to: URL(fileURLWithPath: outDir).appendingPathComponent("sky.png")) }
        if let meter { out["meter"] = ["midtone": meter.midtone, "ev": meter.ev, "metered": meter.metered, "target": target] }
        print(json(out))

    case "asshot":
        // Metadata only: CIRAWFilter's neutral temperature / tint, upright size and orientation, no decode.
        guard !args.isEmpty else { fail(usage, code: 2) }
        for imagePath in args {
            let url = URL(fileURLWithPath: imagePath)
            var line: [String: Any] = ["image": imagePath]
            if LookPipeline.isRAW(url), let raw = CIRAWFilter(imageURL: url) {
                let size = LookPipeline.nativeSize(url: url) ?? .zero
                line["ok"] = true
                line["asShot"] = ["kelvin": Double(raw.neutralTemperature), "tint": Double(raw.neutralTint)]
                line["width"] = Int(size.width); line["height"] = Int(size.height)
                line["orientation"] = Int(raw.orientation.rawValue)
            } else {
                line["ok"] = false; line["error"] = "not a RAW Core Image reads"
            }
            print(json(line))
        }

    case "info":
        guard let imagePath = args.first else { fail(usage, code: 2) }
        let rules = try loadRules(option("--rules"))
        let t0 = Date()
        let dev = try LookPipeline.developAny(url: URL(fileURLWithPath: imagePath), longEdge: nil, rules: rules)
        let url = URL(fileURLWithPath: imagePath)
        let info: [String: Any] = ["image": imagePath, "width": Int(dev.extent.width), "height": Int(dev.extent.height),
                                   "asShot": ["kelvin": dev.asShot.kelvin, "tint": dev.asShot.tint], "developMs": ms(t0),
                                   "raw": LookPipeline.isRAW(url), "decoders": LookPipeline.supportedDecoderVersions(url: url)]
        print(json(info))

    case "ramp":
        let lookText = option("--look") ?? "ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 dhz:+30 shp:30 vig:0"
        let outPath = option("--out")
        let rules = try loadRules(option("--rules"))
        let pipe = try LookPipeline(rules: rules)
        let look = try Look.parse(lookText)
        let asShot = Look.WhiteBalance(kelvin: 5500, tint: 0)
        var patches: [LookMath.RGB] = (0...24).map { .gray(Double($0) / 20) }
        patches += [LookMath.RGB(r: 0.5, g: 0.2, b: 0.2), LookMath.RGB(r: 0.2, g: 0.5, b: 0.2), LookMath.RGB(r: 0.15, g: 0.2, b: 0.6),
                    LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), LookMath.RGB(r: 0.7, g: 0.6, b: 0.1), LookMath.RGB(r: 0.3, g: 0.6, b: 0.7)]
        var rows: [[String: Any]] = []
        var worst = 0.0
        for c in patches {
            let got = pipe.pixel(pipe.apply(look, to: pipe.flat(c, size: 64)), x: 32, y: 32)
            let want = LookMath.flat(c, look: look, asShot: asShot, rules: rules)
            let err = max(abs(got.r - want.r), abs(got.g - want.g), abs(got.b - want.b))
            worst = max(worst, err)
            rows.append(["in": [c.r, c.g, c.b], "graph": [got.r, got.g, got.b], "math": [want.r, want.g, want.b], "err": err])
        }
        // outputTransform alone (the rules' mapper), on colours up to far above white
        var display: [[String: Any]] = []
        let bright: [LookMath.RGB] = [.gray(0), .gray(0.18), .gray(0.6), .gray(0.9), .gray(1), .gray(1.5), .gray(4), .gray(40),
                                      LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), LookMath.RGB(r: 1, g: 0.5, b: 0.05), LookMath.RGB(r: 4, g: 2, b: 0.2),
                                      LookMath.RGB(r: 3, g: 0.24, b: 0.09), LookMath.RGB(r: 0.8, g: 1.6, b: 4), LookMath.RGB(r: 2, g: 1.2, b: 0.84),
                                      LookMath.RGB(r: 0.4, g: 8, b: 0.2), LookMath.RGB(r: 30, g: 0, b: 0)]
        for c in bright {
            let got = pipe.pixel(pipe.output(pipe.flat(c, size: 64).image), x: 32, y: 32)
            let want = LookMath.output(c, rules)
            let err = max(abs(got.r - want.r), abs(got.g - want.g), abs(got.b - want.b))
            worst = max(worst, err)
            display.append(["in": [c.r, c.g, c.b], "graph": [got.r, got.g, got.b], "math": [want.r, want.g, want.b], "err": err])
        }
        // sky blue alone (LookSky's `blu`): its kernel next to LookMath.skyBlue, on sky-like colours
        var sky: [[String: Any]] = []
        let skies: [LookMath.RGB] = [.gray(0), .gray(0.18), .gray(0.9), .gray(1), .gray(1.4), LookMath.RGB(r: 0.12, g: 0.19, b: 0.34),
                                     LookMath.RGB(r: 0.3, g: 0.62, b: 0.78), LookMath.RGB(r: 0.7, g: 0.8, b: 0.85), LookMath.RGB(r: 0.05, g: 0.15, b: 0.6),
                                     LookMath.RGB(r: 0.4, g: 0.3, b: 0.6), LookMath.RGB(r: 0.6, g: 0.35, b: 0.25), LookMath.RGB(r: 0.2, g: 0.5, b: 0.2)]
        for amount in [25.0, 100.0] {
            var l = Look(); l.skyBlue = amount
            for c in skies {
                let got = pipe.pixel(pipe.apply(l, to: pipe.flat(c, size: 64)), x: 32, y: 32)
                let want = LookMath.skyBlue(c, amount: amount)
                let err = max(abs(got.r - want.r), abs(got.g - want.g), abs(got.b - want.b))
                worst = max(worst, err)
                sky.append(["in": [c.r, c.g, c.b], "amount": amount, "graph": [got.r, got.g, got.b], "math": [want.r, want.g, want.b], "err": err])
            }
        }
        let report: [String: Any] = ["look": look.format(), "skyBlue": sky, "asShot": ["kelvin": asShot.kelvin, "tint": asShot.tint],
                                     "rules": rules.stages.mapValues { $0.coefficients }, "perceptualGamma": rules.perceptualGamma,
                                     "order": rules.order, "patches": rows, "mapper": rules.mapper.rawValue, "display": display, "worstGraphVsMath": worst]
        let text = json(report)
        if let outPath { try Data(text.utf8).write(to: URL(fileURLWithPath: outPath)) ; print("ramp → \(outPath) · worst graph vs maths \(String(format: "%.4f", worst))") }
        else { print(text) }

    default:
        print(usage); exit(2)
    }
} catch {
    fail("\(error)")
}
