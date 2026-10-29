import CoreImage
import Foundation

/// The clip maps LookSky's diagnosis (F1) and capture tip (F6) read, measured with Apple's RAW
/// decoder at a small size (prototype, behind `Look.skyFeatures`):
///
/// - `white`: 1 where today's decode (the rules' boost, no extended range) reaches display white
///   on any channel. Today's develop ends at white, so this is detail the current render has lost.
/// - `clipped`: 1 where the decoder's highlight recovery changes the pixel (on vs off, both linear
///   and with extended range). Recovery only rebuilds channels the sensor clipped, so a change
///   there means clipped at capture. Needs macOS 26 (`highlightRecoveryEnabled`); nil before.
/// - `over`: log2 of how far recovery puts a clipped pixel above the clipped decode (0 elsewhere):
///   the decoder's own guess at how much light was lost.
///
/// Three decodes at `longEdge` (about 60 ms each at 512 px on an M-series Mac). No pixels are
/// written anywhere.
nonisolated enum LookSkyClip {
    struct Maps {
        var white: LookMasks.Plane
        var clipped: LookMasks.Plane?
        var over: LookMasks.Plane?
    }

    static let whiteAt: Float = 0.99, changedBy: Float = 0.02

    static func maps(url: URL, longEdge: Int = 512, boost: Double = 1) -> Maps? {
        guard let probe = CIRAWFilter(imageURL: url) else { return nil }
        let native = max(probe.nativeSize.width, probe.nativeSize.height)
        let scale = Float(min(1, Double(longEdge) / max(1, native)))
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let ctx = CIContext(options: [.workingColorSpace: space, .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false])
        func decode(boost: Float, edr: Float, recovery: Bool) -> (px: [Float], w: Int, h: Int)? {
            guard let f = CIRAWFilter(imageURL: url) else { return nil }
            f.scaleFactor = scale; f.boostAmount = boost; f.extendedDynamicRangeAmount = edr
            #if compiler(>=6.2)
            if #available(macOS 26, *) { f.isHighlightRecoveryEnabled = recovery }
            #endif
            guard let img = f.outputImage else { return nil }
            let e = img.extent.integral
            let w = Int(e.width), h = Int(e.height)
            guard w > 0, h > 0 else { return nil }
            var px = [Float](repeating: 0, count: 4 * w * h)
            ctx.render(img, toBitmap: &px, rowBytes: 16 * w, bounds: e, format: .RGBAf, colorSpace: space)
            return (px, w, h)                                       // row 0 = top (Core Image renders top row first)
        }
        guard let today = decode(boost: Float(boost), edr: 0, recovery: true) else { return nil }
        var white = LookMasks.Plane(width: today.w, height: today.h)
        for i in 0..<(today.w * today.h) {
            white.values[i] = max(today.px[4 * i], today.px[4 * i + 1], today.px[4 * i + 2]) >= whiteAt ? 1 : 0
        }
        guard recoverySwitch(probe), let on = decode(boost: 0, edr: 2, recovery: true), let off = decode(boost: 0, edr: 2, recovery: false),
              on.w == off.w, on.h == off.h else { return Maps(white: white, clipped: nil, over: nil) }
        var clipped = LookMasks.Plane(width: on.w, height: on.h), over = clipped
        for i in 0..<(on.w * on.h) {
            let a = max(on.px[4 * i], on.px[4 * i + 1], on.px[4 * i + 2]), b = max(off.px[4 * i], off.px[4 * i + 1], off.px[4 * i + 2])
            var d: Float = 0
            for c in 0..<3 { d = max(d, abs(on.px[4 * i + c] - off.px[4 * i + c])) }
            if d > changedBy * max(b, 0.05) {
                clipped.values[i] = 1
                over.values[i] = b > 1e-4 ? max(0, log2(a / b)) : 0
            }
        }
        return Maps(white: white, clipped: clipped, over: over)
    }

    /// Whether this macOS lets the decoder's highlight recovery be turned off for this file.
    static func recoverySwitch(_ f: CIRAWFilter) -> Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return f.isHighlightRecoverySupported }
        #endif
        return false
    }

    /// Stops of exposure less that would have kept the sky's clipped part under white: the 90th
    /// percentile of `over` inside the sky's clipped pixels, plus the margin to 0.9 × white.
    static func stopsOver(sky: LookMasks.Plane, maps: Maps) -> Double? {
        guard let clipped = maps.clipped, let over = maps.over else { return nil }
        let c = LookSky.resample(clipped, width: sky.width, height: sky.height), o = LookSky.resample(over, width: sky.width, height: sky.height)
        var v: [Float] = []
        for i in 0..<sky.values.count where sky.values[i] >= 0.5 && c.values[i] >= 0.5 { v.append(o.values[i] / max(c.values[i], 1e-3)) }
        guard v.count >= 16 else { return nil }
        v.sort()
        return Double(v[Int(Double(v.count - 1) * 0.9)]) + log2(1 / 0.9)
    }
}
