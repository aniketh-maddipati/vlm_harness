import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// One Core Image graph for every render: preview (`lumina://render`), export (`SetsExport`) and
/// the parity tool (`lumina-render`). Linear working space, the stages of `LookRules.order`, one
/// output transform. Each stage is a parameterised kernel from `LookKernels` whose coefficients
/// come from `rules-v1.json`; the maths is `LookMath`'s.
///
/// The RAW is developed once per (file, size) into a `Developed` (Apple's default profile, no
/// auto), the look stages are re-run per request on top of it: `LookRenderer` keeps developed
/// images by (rel, px) with a byte cap.
nonisolated final class LookPipeline: @unchecked Sendable {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    /// Output colour spaces. The parity references are Lightroom's 16-bit ProPhoto TIFFs (ROMM
    /// RGB, gamma 1.8, D50); previews and JPEG exports are sRGB.
    enum OutputSpace: String, Sendable, CaseIterable {
        case sRGB = "srgb", prophoto = "prophoto", displayP3 = "p3"
        var cgColorSpace: CGColorSpace {
            switch self {
            case .sRGB: return CGColorSpace(name: CGColorSpace.sRGB)!
            case .prophoto: return CGColorSpace(name: CGColorSpace.rommrgb)!
            case .displayP3: return CGColorSpace(name: CGColorSpace.displayP3)!
            }
        }
    }

    /// A developed image: linear, origin at (0, 0), plus the camera's as-shot white balance the
    /// `whiteBalance` stage measures from.
    struct Developed: @unchecked Sendable {
        let image: CIImage
        let asShot: Look.WhiteBalance
        var extent: CGRect { image.extent }
        var longEdge: CGFloat { max(image.extent.width, image.extent.height) }
    }

    let rules: LookRules
    let workingSpace: CGColorSpace
    let context: CIContext
    let kernels: LookKernels

    /// `cacheIntermediates: false` and a memory target are what export uses (roadmap §7); previews
    /// keep the defaults.
    init(rules: LookRules, cacheIntermediates: Bool = true, memoryLimitMB: Int = 0, softwareRenderer: Bool = false) throws {
        try rules.validate()
        self.rules = rules
        guard let ws = Self.colorSpace(named: rules.workingSpace) else { throw Failure("unknown working space \(rules.workingSpace)") }
        workingSpace = ws
        var opts: [CIContextOption: Any] = [
            .workingColorSpace: ws,
            .workingFormat: CIFormat.RGBAh.rawValue,
            .cacheIntermediates: cacheIntermediates,
            .name: "LookPipeline",
        ]
        if memoryLimitMB > 0 { opts[CIContextOption(rawValue: "kCIContextMemoryTarget")] = memoryLimitMB << 20 }
        if softwareRenderer { opts[.useSoftwareRenderer] = true }
        context = CIContext(options: opts)
        kernels = try LookKernels.shared()
    }

    /// `rules.workingSpace` → a linear CGColorSpace. Oklab (the colour stage) assumes sRGB
    /// primaries; a P3 working space is allowed for the loop's experiments but shifts hues there.
    static func colorSpace(named name: String) -> CGColorSpace? {
        switch name {
        case "extendedLinearSRGB": return CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        case "linearSRGB": return CGColorSpace(name: CGColorSpace.linearSRGB)
        case "extendedLinearDisplayP3": return CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        case "linearDisplayP3": return CGColorSpace(name: CGColorSpace.linearDisplayP3)
        default: return nil
        }
    }

    // MARK: rawDevelop

    /// CIRAWFilter with Apple's default profile and no auto adjustments. `longEdge` scales the
    /// decode itself (`scaleFactor`), so a 1024 px preview never demosaics 24 MP.
    static func develop(url: URL, longEdge px: Int?, rules: LookRules) throws -> Developed {
        guard let raw = CIRAWFilter(imageURL: url) else { throw Failure("not a RAW Core Image can read: \(url.lastPathComponent)") }
        let native = raw.nativeSize
        let long = max(native.width, native.height)
        if let px, px > 0, long > 0, CGFloat(px) < long { raw.scaleFactor = Float(CGFloat(px) / long) }
        let draftBelow = rules.k("rawDevelop", "draftBelowPx", 0)
        if let px, draftBelow > 0, Double(px) <= draftBelow { raw.isDraftModeEnabled = true }
        raw.boostAmount = Float(rules.k("rawDevelop", "boostAmount", 1))
        guard let out = raw.outputImage else { throw Failure("couldn't decode \(url.lastPathComponent)") }
        let asShot = Look.WhiteBalance(kelvin: Double(raw.neutralTemperature), tint: Double(raw.neutralTint))
        return Developed(image: Self.atOrigin(out), asShot: asShot)
    }

    /// Any image ImageIO reads (JPEG, TIFF, PNG): for tests, the A/B page and fixtures without
    /// RAWs. Orientation applied, scaled to `longEdge` with Lanczos. As-shot is taken as D55 / 0.
    static func developImage(url: URL, longEdge px: Int?) throws -> Developed {
        guard let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw Failure("can't read \(url.lastPathComponent)") }
        return Developed(image: Self.scaled(Self.atOrigin(img), longEdge: px), asShot: Look.WhiteBalance(kelvin: 5500, tint: 0))
    }

    /// A RAW when Core Image reads it as one, else any image ImageIO reads.
    static func developAny(url: URL, longEdge px: Int?, rules: LookRules) throws -> Developed {
        if isRAW(url) { return try develop(url: url, longEdge: px, rules: rules) }
        return try developImage(url: url, longEdge: px)
    }

    static let rawExtensions: Set<String> = ["arw", "dng", "cr2", "cr3", "nef", "raf", "orf", "rw2", "srw", "pef"]
    static func isRAW(_ url: URL) -> Bool { rawExtensions.contains(url.pathExtension.lowercased()) }

    static func atOrigin(_ img: CIImage) -> CIImage {
        let e = img.extent
        guard e.origin != .zero, !e.isInfinite else { return img }
        return img.transformed(by: CGAffineTransform(translationX: -e.origin.x, y: -e.origin.y))
    }

    static func scaled(_ img: CIImage, longEdge px: Int?) -> CIImage {
        guard let px, px > 0 else { return img }
        let long = max(img.extent.width, img.extent.height)
        guard long > CGFloat(px) else { return img }
        let s = CGFloat(px) / long
        let out = img.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: s, kCIInputAspectRatioKey: 1])
        return atOrigin(out)
    }

    // MARK: the look stages

    /// The graph for one look on one developed image. Cheap to build; the work happens when the
    /// result is rendered. Stages at their reset value are left out, so a neutral look is the
    /// developed image (plus crop).
    func apply(_ look: Look, to dev: Developed) -> CIImage {
        var img = dev.image
        if let c = look.crop { img = cropped(img, c) }
        let extent = img.extent
        let longEdge = max(extent.width, extent.height)
        let gam = CIVector(x: 1 / rules.perceptualGamma, y: rules.perceptualGamma)
        let lum = CIVector(x: rules.luma[0], y: rules.luma[1], z: rules.luma[2], w: 0)
        let ones = CIVector(x: 1, y: 1, z: 1, w: 1), zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let r = rules

        func pass(_ name: String, _ args: [Any]) {
            if let out = kernels.apply(name, extent: extent, args) { img = out }
        }
        func luma(perceptual: Bool) -> CIImage {
            kernels.apply("lookLuma", extent: extent, [img, lum, perceptual ? 1 / r.perceptualGamma : 0]) ?? img
        }
        func blur(_ src: CIImage, sigma: CGFloat) -> CIImage {
            guard sigma > 0.05 else { return src }
            return src.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        }

        for stage in r.lookStages {
            switch stage {
            case "exposure":
                guard look.ev != 0 else { continue }
                let g = LookMath.exposureGain(look.ev, r)
                pass("lookPre", [img, CIVector(x: g, y: g, z: g, w: 1), zero, gam])
            case "whiteBalance":
                guard look.wb != nil else { continue }
                let g = LookMath.whiteBalanceGains(look.wb, asShot: dev.asShot, r)
                pass("lookPre", [img, CIVector(x: g.r, y: g.g, z: g.b, w: 1), zero, gam])
            case "whitesBlacks":
                guard look.whites != 0 || look.blacks != 0 else { continue }
                let wbk = CIVector(x: look.whites * r.k("whitesBlacks", "whitesPerUnit", 0.003),
                                   y: -look.blacks * r.k("whitesBlacks", "blacksPerUnit", 0.002),
                                   z: r.k("whitesBlacks", "whitesPower", 2), w: r.k("whitesBlacks", "blacksPower", 2))
                pass("lookPre", [img, ones, wbk, gam])
            case "tone":
                guard look.highlights != 0 || look.shadows != 0 else { continue }
                let base = blur(luma(perceptual: false), sigma: r.k("tone", "radiusFraction", 0.03) * longEdge)
                let sh = CIVector(x: look.shadows * r.k("tone", "shadowsStopsPerUnit", 0.01), y: r.k("tone", "shadowsLo", 0), z: r.k("tone", "shadowsHi", 0.6), w: 0)
                let hl = CIVector(x: look.highlights * r.k("tone", "highlightsStopsPerUnit", 0.01), y: r.k("tone", "highlightsLo", 0.4), z: r.k("tone", "highlightsHi", 1), w: r.k("tone", "detailGain", 1))
                pass("lookTone", [img, base, sh, hl, gam, lum])
            case "contrast":
                guard look.contrast != 0 else { continue }
                let k = CIVector(x: min(0.95, max(0.05, r.k("contrast", "midpoint", 0.46))),
                                 y: exp2(look.contrast * r.k("contrast", "slopePerUnit", 0.006)),
                                 z: min(1, max(0, r.k("contrast", "lumaMix", 0.5))), w: 0)
                pass("lookContrast", [img, k, gam, lum])
            case "colour":
                guard look.vibrance != 0 || look.saturation != 0 || look.bw else { continue }
                let k1 = CIVector(x: max(0, 1 + look.saturation * r.k("colour", "saturationPerUnit", 0.01)),
                                  y: look.vibrance * r.k("colour", "vibrancePerUnit", 0.01),
                                  z: max(1e-6, r.k("colour", "vibranceChromaMax", 0.25)), w: look.vibrance > 0 ? 1 : 0)
                let k2 = CIVector(x: r.k("colour", "skinHue", 60), y: max(1e-6, r.k("colour", "skinWidth", 25)),
                                  z: r.k("colour", "skinProtect", 0.7), w: look.bw ? 1 : 0)
                pass("lookColour", [img, k1, k2])
            case "clarity":
                guard look.clarity != 0 else { continue }
                let base = blur(luma(perceptual: true), sigma: r.k("clarity", "radiusFraction", 0.02) * longEdge)
                let k = CIVector(x: look.clarity * r.k("clarity", "amountPerUnit", 0.01), y: r.k("clarity", "midtonePower", 2), z: 0, w: 0)
                pass("lookClarity", [img, base, k, gam, lum])
            case "sharpen":
                guard look.sharpen != 0 else { continue }
                let base = blur(luma(perceptual: true), sigma: LookMath.sharpenRadius(longEdge: longEdge, r))
                let k = CIVector(x: look.sharpen * r.k("sharpen", "amountPerUnit", 0.01), y: max(1e-6, r.k("sharpen", "threshold", 0.01)), z: 0, w: 0)
                pass("lookSharpen", [img, base, k, gam, lum])
            case "vignette":
                guard look.vignette != 0 else { continue }
                let m = r.k("vignette", "midpoint", 0.5), f = r.k("vignette", "feather", 0.5)
                let halfDiag = hypot(extent.width, extent.height) / 2
                let k = CIVector(x: look.vignette * r.k("vignette", "stopsPerUnit", 0.02), y: m - f / 2, z: m + f / 2, w: halfDiag > 0 ? 1 / halfDiag : 0)
                pass("lookVignette", [img, k, CIVector(x: extent.midX, y: extent.midY)])
            default:
                continue
            }
        }
        return img
    }

    /// Straighten about the centre, then the box as fractions of the frame (y from the top).
    private func cropped(_ img: CIImage, _ c: Look.Crop) -> CIImage {
        let e = img.extent
        var out = img
        if c.rotate != 0 {
            let t = CGAffineTransform(translationX: e.midX, y: e.midY).rotated(by: -c.rotate * .pi / 180).translatedBy(x: -e.midX, y: -e.midY)
            out = out.transformed(by: t)
        }
        let rect = CGRect(x: e.minX + c.x * e.width, y: e.minY + (1 - c.y - c.h) * e.height, width: c.w * e.width, height: c.h * e.height).integral
        return Self.atOrigin(out.cropped(to: rect))
    }

    // MARK: outputTransform

    /// Clamped to 0…1 in the working space; the colour space conversion happens in the encode.
    func clamped(_ img: CIImage) -> CIImage { img.applyingFilter("CIColorClamp") }

    func jpeg(_ img: CIImage, quality: Double = 0.9, space: OutputSpace = .sRGB) throws -> Data {
        let q = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        guard let d = context.jpegRepresentation(of: clamped(img), colorSpace: space.cgColorSpace, options: [q: quality]) else { throw Failure("JPEG encode failed") }
        return d
    }

    /// 16-bit TIFF (RGBA16, the alpha channel is all ones) in `space`, tagged with its profile.
    func tiff16(_ img: CIImage, space: OutputSpace) throws -> Data {
        guard let d = context.tiffRepresentation(of: clamped(img), format: .RGBA16, colorSpace: space.cgColorSpace, options: [:]) else { throw Failure("TIFF encode failed") }
        return d
    }

    func png(_ img: CIImage, space: OutputSpace = .sRGB) throws -> Data {
        guard let d = context.pngRepresentation(of: clamped(img), format: .RGBA8, colorSpace: space.cgColorSpace, options: [:]) else { throw Failure("PNG encode failed") }
        return d
    }

    /// Rasterises a developed image once (half floats in the working space) so the look stages
    /// re-run on a bitmap, not on the RAW decode. Returns the image and its size in bytes.
    func rasterised(_ dev: Developed) throws -> (Developed, Int) {
        let e = dev.extent.integral
        guard let cg = context.createCGImage(dev.image, from: e, format: .RGBAh, colorSpace: workingSpace) else { throw Failure("rasterise failed") }
        return (Developed(image: CIImage(cgImage: cg), asShot: dev.asShot), cg.bytesPerRow * cg.height)
    }

    // MARK: reading pixels (tests, the ramp dump)

    /// Linear working-space values of one row.
    func row(_ img: CIImage, y: Int, x0: Int = 0, width: Int) -> [LookMath.RGB] {
        var px = [Float](repeating: 0, count: 4 * width)
        context.render(img, toBitmap: &px, rowBytes: 16 * width, bounds: CGRect(x: x0, y: y, width: width, height: 1), format: .RGBAf, colorSpace: workingSpace)
        return (0..<width).map { LookMath.RGB(r: Double(px[4 * $0]), g: Double(px[4 * $0 + 1]), b: Double(px[4 * $0 + 2])) }
    }

    func pixel(_ img: CIImage, x: Int, y: Int) -> LookMath.RGB { row(img, y: y, x0: x, width: 1)[0] }

    // MARK: synthetic images

    /// A flat patch in the working space.
    func flat(_ c: LookMath.RGB, size: Int = 64) -> Developed {
        let color = CIColor(red: c.r, green: c.g, blue: c.b, alpha: 1, colorSpace: workingSpace) ?? CIColor(red: c.r, green: c.g, blue: c.b)
        return Developed(image: CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: size, height: size)), asShot: Look.WhiteBalance(kelvin: 5500, tint: 0))
    }

    /// A horizontal ramp of `steps` columns, each `columnWidth` px wide, from `lo` to `hi` in
    /// linear light, `height` px tall. Grey unless `tint` scales the channels.
    func ramp(steps: Int = 64, columnWidth: Int = 8, height: Int = 32, lo: Double = 0, hi: Double = 1, tint: LookMath.RGB = .gray(1)) -> Developed {
        let w = steps * columnWidth
        var data = [Float](repeating: 1, count: w * height * 4)
        for y in 0..<height {
            for x in 0..<w {
                let v = lo + (hi - lo) * Double(x / columnWidth) / Double(max(1, steps - 1))
                let i = 4 * (y * w + x)
                data[i] = Float(v * tint.r); data[i + 1] = Float(v * tint.g); data[i + 2] = Float(v * tint.b); data[i + 3] = 1
            }
        }
        let bytes = data.withUnsafeBufferPointer { Data(buffer: $0) }
        let img = CIImage(bitmapData: bytes, bytesPerRow: w * 16, size: CGSize(width: w, height: height), format: .RGBAf, colorSpace: workingSpace)
        return Developed(image: img, asShot: Look.WhiteBalance(kelvin: 5500, tint: 0))
    }
}
