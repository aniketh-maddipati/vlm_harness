import CoreImage
import Foundation

let usage = """
lumina-render — render an ARW through the app's LookPipeline (Tools/parity)

  lumina-render render <image> [--look "<look string>"] [--px 2048] [--space prophoto|srgb|p3]
                       [--out file.tif|.jpg|.png] [--rules rules-v1.json] [--json]
      One render. A 16-bit TIFF unless --out ends in .jpg / .png. Prints develop and render
      times (and JSON with --json). <image> may be any RAW Core Image reads, or a JPEG/TIFF/PNG.

  lumina-render batch <jobs.json> [--rules rules-v1.json]
      Many renders, one process: [{"image", "look", "px", "out", "space"}]. Each (image, px) is
      developed once. Prints one JSON line per job with timings; exit 1 if any job failed.

  lumina-render info <image>
      As-shot white balance, native size, develop time.

  lumina-render ramp [--look "<look string>"] [--rules rules-v1.json] [--out ramp.json]
      The graph on flat patches (a grey ramp and test colours) next to LookMath's scalar chain,
      as JSON, for Tools/parity/lookmath.py --check: proves the Metal, Swift and numpy copies of
      the stage maths agree.

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
        guard let imagePath = args.first else { fail(usage, code: 2) }
        let rules = try loadRules(rulesPath)
        let pipe = try LookPipeline(rules: rules)
        let look = try Look.parse(lookText)
        let t0 = Date()
        let dev = try LookPipeline.developAny(url: URL(fileURLWithPath: imagePath), longEdge: px, rules: rules)
        let (raster, bytes) = try pipe.rasterised(dev)
        let developMs = ms(t0)
        let t1 = Date()
        let img = pipe.apply(look, to: raster)
        let out = URL(fileURLWithPath: outPath ?? ((imagePath as NSString).deletingPathExtension + ".lumina.tif"))
        let data = try encode(pipe, img, to: out, space: space)
        let renderMs = ms(t1)
        let info: [String: Any] = ["image": imagePath, "out": out.path, "look": look.format(), "px": px, "space": space.rawValue,
                                   "width": Int(img.extent.width), "height": Int(img.extent.height), "bytes": data.count, "rasterBytes": bytes,
                                   "asShot": ["kelvin": dev.asShot.kelvin, "tint": dev.asShot.tint], "developMs": developMs, "renderMs": renderMs]
        if wantJSON { print(json(info)) }
        else { print("\(out.lastPathComponent): \(Int(img.extent.width))×\(Int(img.extent.height)) \(space.rawValue) · develop \(developMs) ms · render+encode \(renderMs) ms · as shot \(Int(dev.asShot.kelvin)) K \(Int(dev.asShot.tint))") }

    case "batch":
        let rulesPath = option("--rules")
        guard let plan = args.first, let data = FileManager.default.contents(atPath: plan),
              let jobs = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { fail("batch wants a JSON array of jobs", code: 2) }
        let rules = try loadRules(rulesPath)
        let pipe = try LookPipeline(rules: rules)
        var developed: [String: (LookPipeline.Developed, Int)] = [:]
        var failed = 0
        for job in jobs {
            let image = job["image"] as? String ?? "", lookText = job["look"] as? String ?? "", px = job["px"] as? Int ?? 2048
            let space = LookPipeline.OutputSpace(rawValue: job["space"] as? String ?? "prophoto") ?? .prophoto
            let out = job["out"] as? String ?? ((image as NSString).deletingPathExtension + ".lumina.tif")
            var line: [String: Any] = ["image": image, "look": lookText, "px": px, "out": out]
            do {
                let key = "\(image)|\(px)"
                var developMs = 0
                if developed[key] == nil {
                    let t0 = Date()
                    let dev = try LookPipeline.developAny(url: URL(fileURLWithPath: image), longEdge: px, rules: rules)
                    developed[key] = try pipe.rasterised(dev)
                    developMs = ms(t0)
                    // One developed image per size at a time: the sweep walks image by image.
                    if developed.count > 2 { for k in developed.keys where k != key { developed[k] = nil } }
                }
                let (dev, _) = developed[key]!
                let t1 = Date()
                let img = pipe.apply(try Look.parse(lookText), to: dev)
                _ = try encode(pipe, img, to: URL(fileURLWithPath: out), space: space)
                line["ok"] = true; line["developMs"] = developMs; line["renderMs"] = ms(t1)
                line["asShot"] = ["kelvin": dev.asShot.kelvin, "tint": dev.asShot.tint]
                line["width"] = Int(img.extent.width); line["height"] = Int(img.extent.height)
            } catch {
                failed += 1
                line["ok"] = false; line["error"] = "\(error)"
            }
            print(json(line))
        }
        exit(failed == 0 ? 0 : 1)

    case "info":
        guard let imagePath = args.first else { fail(usage, code: 2) }
        let rules = try loadRules(option("--rules"))
        let t0 = Date()
        let dev = try LookPipeline.developAny(url: URL(fileURLWithPath: imagePath), longEdge: nil, rules: rules)
        let info: [String: Any] = ["image": imagePath, "width": Int(dev.extent.width), "height": Int(dev.extent.height),
                                   "asShot": ["kelvin": dev.asShot.kelvin, "tint": dev.asShot.tint], "developMs": ms(t0),
                                   "raw": LookPipeline.isRAW(URL(fileURLWithPath: imagePath))]
        print(json(info))

    case "ramp":
        let lookText = option("--look") ?? "ev:+0.70 wb:5200/+3 con:+12 hl:-40 sh:+25 wh:0 bl:-8 vib:+10 sat:0 clr:+15 shp:30 vig:0"
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
        let report: [String: Any] = ["look": look.format(), "asShot": ["kelvin": asShot.kelvin, "tint": asShot.tint],
                                     "rules": rules.stages.mapValues { $0.coefficients }, "perceptualGamma": rules.perceptualGamma,
                                     "order": rules.order, "patches": rows, "worstGraphVsMath": worst]
        let text = json(report)
        if let outPath { try Data(text.utf8).write(to: URL(fileURLWithPath: outPath)) ; print("ramp → \(outPath) · worst graph vs maths \(String(format: "%.4f", worst))") }
        else { print(text) }

    default:
        print(usage); exit(2)
    }
} catch {
    fail("\(error)")
}
