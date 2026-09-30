import AppKit
import CoreImage

/// ANSWERS-phase0 §3 fixture: the same edit rendered by WebKit (CSS filter from
/// LuminaCore.editFilter) and by SetsEditLook (Core Image) must agree within ΔE < 1.
@MainActor
enum LookParity {
    struct Row: Encodable { let recipe: String; let css: String; let space: String; let meanDE: Double; let p95DE: Double; let maxDE: Double }

    static func run(host: ProbeHost, image: URL, recipes: [[String: Double]], width: Int, outDir: URL) async throws -> [Row] {
        // Source scaled once, losslessly, to exactly width × h so neither side resamples.
        guard let src = CIImage(contentsOf: image) else { throw ProbeError("can't read \(image.path)") }
        let s = Double(width) / src.extent.width
        let scaled = src.transformed(by: CGAffineTransform(scaleX: s, y: s))
        let w = width, h = Int((src.extent.height * s).rounded(.down))
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let ctx = CIContext()
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let png = ctx.pngRepresentation(of: scaled.cropped(to: rect), format: .RGBA8, colorSpace: srgb) else { throw ProbeError("png") }
        guard let base = ctx.createCGImage(CIImage(data: png)!, from: rect, format: .RGBA8, colorSpace: srgb) else { throw ProbeError("base") }
        try Pixels.writePNG(base, to: outDir.appendingPathComponent("look-base.png"))
        let dpr = (try await host.js("return window.devicePixelRatio") as? Double) ?? 2
        var rows: [Row] = []
        for (i, r) in recipes.enumerated() {
            let rj = String(data: try JSONSerialization.data(withJSONObject: r, options: .sortedKeys), encoding: .utf8)!
            guard let css = try await host.js("return LuminaCore.editFilter(\(rj))") as? String else { throw ProbeError("editFilter") }
            // WebKit side: a fixed overlay, 1 image px = 1 device px.
            try await host.js("""
              let el=document.getElementById('__look'); if(!el){ el=document.createElement('img'); el.id='__look'; document.body.appendChild(el); }
              el.style.cssText='position:fixed;left:0;top:0;z-index:2147483647;image-rendering:pixelated;width:\(Double(w) / dpr)px;height:\(Double(h) / dpr)px;filter:\(css)';
              el.src='data:image/png;base64,\(png.base64EncodedString())';
              await el.decode(); await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
            """, timeout: 20)
            let shot = try await host.snapshot(scale: dpr)
            guard let web = shot.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)) else { throw ProbeError("crop") }
            try Pixels.writePNG(web, to: outDir.appendingPathComponent("look-\(i)-webkit.png"))
            for space in [SetsEditLook.Space.sRGB, .linear] {
                let out = SetsEditLook.apply(try SetsEditLook.parse(css), to: CIImage(cgImage: base), space: space)
                guard let native = ctx.createCGImage(out, from: rect, format: .RGBA8, colorSpace: srgb) else { throw ProbeError("render") }
                if space == .sRGB { try Pixels.writePNG(native, to: outDir.appendingPathComponent("look-\(i)-native.png")) }
                let de = deltaE(web, native)
                rows.append(Row(recipe: rj, css: css, space: space == .sRGB ? "sRGB" : "linear", meanDE: de.mean, p95DE: de.p95, maxDE: de.max))
            }
        }
        // Noise floor: the same image with no filter through both paths.
        try await host.js("const el=document.getElementById('__look'); el.style.filter='none'; await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));")
        let shot = try await host.snapshot(scale: dpr)
        if let web = shot.cropping(to: rect) {
            let de = deltaE(web, base)
            rows.append(Row(recipe: "none", css: "none", space: "floor", meanDE: de.mean, p95DE: de.p95, maxDE: de.max))
        }
        try await host.js("document.getElementById('__look')?.remove()")
        return rows
    }

    /// CIEDE2000 over all pixels.
    static func deltaE(_ a: CGImage, _ b: CGImage) -> (mean: Double, p95: Double, max: Double) {
        let s = stats(a, b)
        return (s.mean, s.p95, s.max)
    }

    struct DE: Encodable { let mean: Double; let median: Double; let p95: Double; let max: Double; let pixels: Int }

    /// CIEDE2000 over the common area of two sRGB images (a pixel of size difference from
    /// rounding is tolerated: the smaller size is compared), with the median too.
    static func stats(_ a: CGImage, _ b: CGImage) -> DE {
        let w = min(a.width, b.width), h = min(a.height, b.height)
        guard w > 0, h > 0, let ca = a.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)), let cb = b.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)) else {
            return DE(mean: 100, median: 100, p95: 100, max: 100, pixels: 0)
        }
        let pa = Pixels.rgba(ca), pb = Pixels.rgba(cb)
        var d: [Double] = []
        d.reserveCapacity(pa.count / 4)
        var i = 0
        while i + 3 < pa.count, i + 3 < pb.count {
            d.append(de2000(lab(pa[i], pa[i + 1], pa[i + 2]), lab(pb[i], pb[i + 1], pb[i + 2])))
            i += 4
        }
        guard !d.isEmpty else { return DE(mean: 100, median: 100, p95: 100, max: 100, pixels: 0) }
        d.sort()
        return DE(mean: d.reduce(0, +) / Double(d.count), median: d[d.count / 2], p95: d[Int(Double(d.count - 1) * 0.95)], max: d.last ?? 0, pixels: d.count)
    }

    static func lab(_ r8: UInt8, _ g8: UInt8, _ b8: UInt8) -> (Double, Double, Double) {
        func lin(_ v: UInt8) -> Double { let c = Double(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(r8), g = lin(g8), b = lin(b8)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    static func de2000(_ p: (Double, Double, Double), _ q: (Double, Double, Double)) -> Double {
        let (L1, a1, b1) = p, (L2, a2, b2) = q
        let C1 = hypot(a1, b1), C2 = hypot(a2, b2), Cb = (C1 + C2) / 2
        let G = 0.5 * (1 - sqrt(pow(Cb, 7) / (pow(Cb, 7) + pow(25, 7))))
        let a1p = (1 + G) * a1, a2p = (1 + G) * a2
        let C1p = hypot(a1p, b1), C2p = hypot(a2p, b2)
        func hue(_ b: Double, _ a: Double) -> Double { let h = atan2(b, a) * 180 / .pi; return h < 0 ? h + 360 : h }
        let h1 = hue(b1, a1p), h2 = hue(b2, a2p)
        let dL = L2 - L1, dC = C2p - C1p
        var dh = h2 - h1
        if C1p * C2p == 0 { dh = 0 } else if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        let dH = 2 * sqrt(C1p * C2p) * sin(dh / 2 * .pi / 180)
        let Lb = (L1 + L2) / 2, Cbp = (C1p + C2p) / 2
        var hb = h1 + h2
        if C1p * C2p != 0 { hb = abs(h1 - h2) > 180 ? (h1 + h2 + (h1 + h2 < 360 ? 360 : -360)) / 2 : (h1 + h2) / 2 }
        let T = 1 - 0.17 * cos((hb - 30) * .pi / 180) + 0.24 * cos(2 * hb * .pi / 180) + 0.32 * cos((3 * hb + 6) * .pi / 180) - 0.20 * cos((4 * hb - 63) * .pi / 180)
        let SL = 1 + 0.015 * pow(Lb - 50, 2) / sqrt(20 + pow(Lb - 50, 2)), SC = 1 + 0.045 * Cbp, SH = 1 + 0.015 * Cbp * T
        let RT = -2 * sqrt(pow(Cbp, 7) / (pow(Cbp, 7) + pow(25, 7))) * sin(60 * exp(-pow((hb - 275) / 25, 2)) * .pi / 180)
        return sqrt(pow(dL / SL, 2) + pow(dC / SC, 2) + pow(dH / SH, 2) + RT * (dC / SC) * (dH / SH))
    }
}
