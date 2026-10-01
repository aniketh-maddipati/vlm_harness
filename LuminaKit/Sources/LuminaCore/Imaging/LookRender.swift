import Foundation
import CoreGraphics
import CoreImage

// WP-4. A look, approximately, with stock Core Image filters: enough that every slider, Before
// and Variations show a difference in the package's own previews. It is not the app's look
// pipeline (`Lumina/Sets/Look`); the app swaps that in behind `ImageProvider`.

public enum LookRender {
    static let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// A stable name for a look, for cache keys.
    public static func key(_ look: Look?) -> String {
        guard let look, !look.isEmpty else { return "" }
        return look.keys.sorted().map { "\($0)=\(String(format: "%.4g", look[$0]!))" }.joined(separator: ",")
    }

    /// `base` (upright, uncropped) with `look` applied: turns, straighten and crop first, then
    /// tone and colour, then the vignette on what is left. Nil when Core Image can't render.
    public static func apply(_ look: Look, to base: CGImage, maxPixel: Int) -> CGImage? {
        var img = CIImage(cgImage: base)
        let box = CropBox(look)
        img = geometry(img, box)
        img = tone(img, look)
        let long = max(img.extent.width, img.extent.height)
        if long > CGFloat(maxPixel), long > 0 {
            let k = CGFloat(maxPixel) / long
            img = img.transformed(by: CGAffineTransform(scaleX: k, y: k), highQualityDownsample: true)
        }
        let r = img.extent.integral
        guard r.width >= 1, r.height >= 1, !r.isInfinite else { return nil }
        return context.createCGImage(img, from: r, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    static func geometry(_ input: CIImage, _ box: CropBox) -> CIImage {
        var img = input
        switch box.turns {
        case 1: img = img.oriented(.right)
        case 2: img = img.oriented(.down)
        case 3: img = img.oriented(.left)
        default: break
        }
        img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        let frame = img.extent
        if abs(box.angle) >= 0.05 {
            // Clockwise on screen is negative in Core Image's y-up space.
            let k = CropBox.coverScale(angle: box.angle, aspect: Double(frame.width / max(frame.height, 1)))
            let t = CGAffineTransform(translationX: frame.midX, y: frame.midY)
                .rotated(by: -box.angle * .pi / 180).scaledBy(x: k, y: k)
                .translatedBy(x: -frame.midX, y: -frame.midY)
            img = img.transformed(by: t).cropped(to: frame)
        }
        if !box.isFullFrame {
            let r = CGRect(x: frame.width * box.x, y: frame.height * (1 - box.y - box.h), width: frame.width * box.w, height: frame.height * box.h).integral
            img = img.cropped(to: r.intersection(frame))
        }
        return img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
    }

    static func tone(_ input: CIImage, _ look: Look) -> CIImage {
        func v(_ k: String) -> Double { look[k] ?? EditSetting.byKey[k]?.def ?? 0 }
        var img = input
        let extent = input.extent
        func filter(_ name: String, _ params: [String: Any]) {
            guard let f = CIFilter(name: name) else { return }
            f.setValue(img, forKey: kCIInputImageKey)
            for (k, val) in params { f.setValue(val, forKey: k) }
            if let out = f.outputImage { img = out.cropped(to: extent) }
        }
        // The working space is sRGB (gamma-encoded), so a stop is less than a doubling: 0.7, as the prototype.
        if v("ev") != 0 { filter("CIExposureAdjust", [kCIInputEVKey: v("ev") * 0.7]) }
        let wb = v("wb"), tint = v("tint")
        if abs(wb - EditSetting.asShotKelvin) > 1 || tint != 0 {
            // A higher Kelvin on the slider warms the picture: tell the filter the light was bluer.
            let t = 6500 * wb / EditSetting.asShotKelvin
            filter("CITemperatureAndTint", ["inputNeutral": CIVector(x: t, y: -tint * 0.6), "inputTargetNeutral": CIVector(x: 6500, y: 0)])
        }
        let sh = v("sh"), hl = v("hl"), dark = v("cDark"), mid = v("cMid"), light = v("cLight")
        if sh != 0 || hl != 0 || dark != 0 || mid != 0 || light != 0 {
            let y1 = clamp(0.03, 0.25 + sh * 0.0012 + dark * 0.0025, 0.6)
            let y2 = clamp(y1 + 0.03, 0.5 + mid * 0.0025 + (sh + hl) * 0.0002, 0.9)
            let y3 = clamp(y2 + 0.03, 0.75 + hl * 0.0012 + light * 0.0025, 0.97)
            filter("CIToneCurve", ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0.25, y: y1), "inputPoint2": CIVector(x: 0.5, y: y2),
                                   "inputPoint3": CIVector(x: 0.75, y: y3), "inputPoint4": CIVector(x: 1, y: 1)])
        }
        let con = v("con"), bands = EditSetting.colours.reduce(0.0) { $0 + v("sat_\($1)") } / Double(EditSetting.colours.count)
        let sat = max(0, 1 + v("sat") / 100 + bands / 150)
        if con != 0 || abs(sat - 1) > 0.001 {
            filter("CIColorControls", [kCIInputContrastKey: 1 + con / 250, kCIInputSaturationKey: sat, kCIInputBrightnessKey: 0])
        }
        let hue = EditSetting.colours.reduce(0.0) { $0 + v("hue_\($1)") } / Double(EditSetting.colours.count)
        if hue != 0 { filter("CIHueAdjust", [kCIInputAngleKey: hue / 100 * 0.5]) }
        let lum = EditSetting.colours.reduce(0.0) { $0 + v("lum_\($1)") } / Double(EditSetting.colours.count)
        if lum != 0 { filter("CIGammaAdjust", ["inputPower": pow(2, -lum / 100)]) }
        let shp = v("shp") - (EditSetting.byKey["shp"]?.def ?? 40)
        if shp != 0 { filter("CISharpenLuminance", [kCIInputSharpnessKey: max(0, 0.4 + shp / 100), kCIInputRadiusKey: 1.6]) }
        if v("nr") > 0 { filter("CINoiseReduction", ["inputNoiseLevel": v("nr") / 100 * 0.06, kCIInputSharpnessKey: 0.3]) }
        let vig = v("vig")
        if vig != 0 {
            // Negative darkens the corners (as in Lightroom); Midpoint moves where it starts.
            let radius = (0.6 + v("vMid") / 100 * 1.6) * (0.6 + v("vFeather") / 100 * 0.8)
            filter("CIVignette", [kCIInputIntensityKey: -vig / 100 * 1.6, kCIInputRadiusKey: radius])
        }
        return img
    }
}
