import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Metal

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
    /// The Metal device the context renders on (nil with the software renderer): the Edit canvas
    /// makes its base textures and drawables on the same one.
    let device: MTLDevice?

    /// `cacheIntermediates: false` and a memory target are what export uses (roadmap §7); previews
    /// keep the defaults. `device` pins the context to one Metal device (the canvas shares it
    /// with its textures); nil takes the system default.
    init(rules: LookRules, cacheIntermediates: Bool = true, memoryLimitMB: Int = 0, softwareRenderer: Bool = false, device: MTLDevice? = nil) throws {
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
        if softwareRenderer {
            context = CIContext(options: opts)
            self.device = nil
        } else if let dev = device ?? MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: dev, options: opts)
            self.device = dev
        } else {
            context = CIContext(options: opts)
            self.device = nil
        }
        kernels = try LookKernels.shared()
    }

    // MARK: decoder versions (RAW 9)

    /// The integer in a `CIRAWDecoderVersion` ("8" → 8). Nil for `.versionNone`.
    static func decoderNumber(_ v: CIRAWDecoderVersion) -> Int? { Int(v.rawValue.filter(\.isNumber)) }

    /// Every decoder version Core Image offers for this file, ascending. Empty when the file is
    /// not a RAW Core Image reads.
    static func supportedDecoderVersions(url: URL) -> [Int] {
        guard let raw = CIRAWFilter(imageURL: url) else { return [] }
        return raw.supportedDecoderVersions.compactMap(decoderNumber).sorted()
    }

    /// The upright size of the RAW (`nativeSize` with the EXIF turn applied), without decoding.
    static func nativeSize(url: URL) -> CGSize? {
        guard let raw = CIRAWFilter(imageURL: url) else { return nil }
        let n = raw.nativeSize
        switch raw.orientation {
        case .left, .right, .leftMirrored, .rightMirrored: return CGSize(width: n.height, height: n.width)
        default: return n
        }
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
    /// `decoderVersion` picks one of `supportedDecoderVersions` (RAW 9 tiers; nil = Core Image's
    /// default), `nr` is the look's Detail ▸ luminance noise reduction (0 … 100).
    static func develop(url: URL, longEdge px: Int?, rules: LookRules, decoderVersion: Int? = nil, nr: Double? = nil) throws -> Developed {
        guard let raw = CIRAWFilter(imageURL: url) else { throw Failure("not a RAW Core Image can read: \(url.lastPathComponent)") }
        if let want = decoderVersion {
            guard let v = raw.supportedDecoderVersions.first(where: { decoderNumber($0) == want }) else {
                throw Failure("\(url.lastPathComponent): decoder version \(want) is not supported here (have \(raw.supportedDecoderVersions.compactMap(decoderNumber).sorted()))")
            }
            raw.decoderVersion = v
        }
        if let nr { raw.luminanceNoiseReductionAmount = Float(min(1, max(0, nr / 100))) }
        let native = raw.nativeSize
        let long = max(native.width, native.height)
        if let px, px > 0, long > 0, CGFloat(px) < long { raw.scaleFactor = Float(CGFloat(px) / long) }
        let draftBelow = rules.k("rawDevelop", "draftBelowPx", 0)
        if let px, draftBelow > 0, Double(px) <= draftBelow { raw.isDraftModeEnabled = true }
        raw.boostAmount = Float(rules.k("rawDevelop", "boostAmount", 1))
        // The lens's corner shading, undone with the camera's own numbers, in the decoder's linear
        // space (before its tone curve), as Lightroom's lens profile does. 0 leaves the shading in.
        let shading = rules.k("rawDevelop", "lensShading", 0)
        if shading > 0, let s = LookLensShading.read(url: url), s.corrects {
            raw.linearSpaceFilter = LookShadingFilter(shading: s, amount: shading)
        }
        guard let out = raw.outputImage, !out.extent.isEmpty, !out.extent.isInfinite else { throw Failure("couldn't decode \(url.lastPathComponent)") }
        let asShot = Look.WhiteBalance(kelvin: Double(raw.neutralTemperature), tint: Double(raw.neutralTint))
        return Developed(image: try baseMatched(Self.atOrigin(out), rules: rules), asShot: asShot)
    }

    /// The decoder's rendering brought to Lightroom's default (`LookMath.baseMatch`), as the last
    /// step of rawDevelop: every base, tile and export starts from the same matched picture.
    static func baseMatched(_ img: CIImage, rules: LookRules) throws -> CIImage {
        let m = LookMath.BaseMatch(rules)
        guard !m.isIdentity else { return img }
        let w = m.rows, lum = rules.luma
        let args: [Any] = [img, CIVector(x: w[0][0], y: w[0][1], z: w[0][2], w: 0), CIVector(x: w[1][0], y: w[1][1], z: w[1][2], w: 0),
                           CIVector(x: w[2][0], y: w[2][1], z: w[2][2], w: 0),
                           CIVector(x: m.lift, y: m.s, z: 1 / rules.perceptualGamma, w: rules.perceptualGamma),
                           CIVector(x: lum[0], y: lum[1], z: lum[2], w: 0),
                           CIVector(x: m.hiDesat, y: m.hiFrom, z: m.loDesat, w: m.loBelow)]
        guard let out = try LookKernels.shared().apply("lookBase", extent: img.extent, args) else { throw Failure("base match failed") }
        return out
    }

    /// The radial gain of `LookLensShading` as an image over `extent` (the centre of the frame is
    /// the centre of the lens): a small float map, scaled up smoothly.
    static func shadingGain(_ s: LookLensShading, amount: Double, extent: CGRect) -> CIImage? {
        guard extent.width > 1, extent.height > 1, !extent.isInfinite else { return nil }
        let w = 96, h = max(2, Int((96 * extent.height / extent.width).rounded()))
        var px = [Float](repeating: 1, count: w * h * 4)
        let cx = Double(w) / 2, cy = Double(h) / 2, half = (cx * cx + cy * cy).squareRoot()
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                let g = Float(s.gain(at: (dx * dx + dy * dy).squareRoot() / half, amount: amount))
                let i = 4 * (y * w + x)
                px[i] = g; px[i + 1] = g; px[i + 2] = g
            }
        }
        let data = px.withUnsafeBufferPointer { Data(buffer: $0) }
        let map = CIImage(bitmapData: data, bytesPerRow: w * 16, size: CGSize(width: w, height: h), format: .RGBAf, colorSpace: nil)
        return map.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(w), y: extent.height / CGFloat(h)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    /// A photo's embedded JPEG (its byte range in the RAW, as the page's `parseHead` found it),
    /// turned upright, scaled to `longEdge`: the canvas's stand-in when the RAW itself can't be
    /// developed (a corrupt file with a good preview, or the synthetic ARWs the CI probe uses).
    static func developPreview(url: URL, offset: Int, length: Int, orientation: Int, longEdge px: Int?) throws -> Developed {
        guard offset >= 0, length > 0, length <= 64 << 20 else { throw Failure("no preview range in \(url.lastPathComponent)") }
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        try h.seek(toOffset: UInt64(offset))
        guard let data = try h.read(upToCount: length), data.count == length, var img = CIImage(data: data) else { throw Failure("preview doesn't decode: \(url.lastPathComponent)") }
        if let o = CGImagePropertyOrientation(rawValue: UInt32(max(1, min(8, orientation)))), o != .up { img = img.oriented(o) }
        return Developed(image: Self.scaled(Self.atOrigin(img), longEdge: px), asShot: Look.WhiteBalance(kelvin: 5500, tint: 0))
    }

    /// Any image ImageIO reads (JPEG, TIFF, PNG): for tests, the A/B page and fixtures without
    /// RAWs. Orientation applied, scaled to `longEdge` with Lanczos. As-shot is taken as D55 / 0.
    static func developImage(url: URL, longEdge px: Int?) throws -> Developed {
        guard let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw Failure("can't read \(url.lastPathComponent)") }
        return Developed(image: Self.scaled(Self.atOrigin(img), longEdge: px), asShot: Look.WhiteBalance(kelvin: 5500, tint: 0))
    }

    /// A RAW when Core Image reads it as one, else any image ImageIO reads.
    static func developAny(url: URL, longEdge px: Int?, rules: LookRules, decoderVersion: Int? = nil, nr: Double? = nil) throws -> Developed {
        if isRAW(url) { return try develop(url: url, longEdge: px, rules: rules, decoderVersion: decoderVersion, nr: nr) }
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
    /// result is rendered. Stages at their reset value are left out (`Look.runs`), so a neutral
    /// look is the developed image (plus crop). Core Image fuses the stages that run into one
    /// program per set of stages, compiled the first time it renders (`LookWarmPlan`).
    func apply(_ look: Look, to dev: Developed, crop: Bool = true) -> CIImage {
        var img = dev.image
        if crop, let c = look.crop { img = cropped(img, c) }
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

        for stage in r.lookStages where look.runs(stage) {
            switch stage {
            case "exposure":
                pass("lookExposure", [img, CIVector(x: LookMath.exposureGain(look.ev, r), y: LookMath.exposureWhite(r))])
            case "whiteBalance":
                let g = LookMath.whiteBalanceGains(look.wb, asShot: dev.asShot, r)
                pass("lookWhiteBalance", [img, CIVector(x: g.r, y: g.g, z: g.b, w: 1), CIVector(x: LookMath.whiteBalanceWhite(r), y: 0)])
            case "whitesBlacks":
                let wbk = CIVector(x: look.whites * r.k("whitesBlacks", "whitesPerUnit", 0.003),
                                   y: -look.blacks * r.k("whitesBlacks", "blacksPerUnit", 0.002),
                                   z: r.k("whitesBlacks", "whitesPower", 2), w: r.k("whitesBlacks", "blacksPower", 2))
                pass("lookPre", [img, ones, wbk, gam])
            case "tone":
                let base = blur(luma(perceptual: false), sigma: r.k("tone", "radiusFraction", 0.03) * longEdge)
                let sh = CIVector(x: look.shadows * r.k("tone", "shadowsStopsPerUnit", 0.01), y: r.k("tone", "shadowsLo", 0), z: r.k("tone", "shadowsHi", 0.6), w: 0)
                let hl = CIVector(x: look.highlights * r.k("tone", "highlightsStopsPerUnit", 0.01), y: r.k("tone", "highlightsLo", 0.4), z: r.k("tone", "highlightsHi", 1), w: r.k("tone", "detailGain", 1))
                pass("lookTone", [img, base, sh, hl, gam, lum])
            case "contrast":
                let k = CIVector(x: min(0.95, max(0.05, r.k("contrast", "midpoint", 0.46))),
                                 y: exp2(look.contrast * r.k("contrast", "slopePerUnit", 0.006)),
                                 z: min(1, max(0, r.k("contrast", "lumaMix", 0.5))), w: 0)
                pass("lookContrast", [img, k, gam, lum])
            case "colour":
                let k1 = CIVector(x: max(0, 1 + look.saturation * r.k("colour", "saturationPerUnit", 0.01)),
                                  y: look.vibrance * r.k("colour", "vibrancePerUnit", 0.01),
                                  z: max(1e-6, r.k("colour", "vibranceChromaMax", 0.25)), w: look.vibrance > 0 ? 1 : 0)
                let k2 = CIVector(x: r.k("colour", "skinHue", 60), y: max(1e-6, r.k("colour", "skinWidth", 25)),
                                  z: r.k("colour", "skinProtect", 0.7), w: look.bw ? 1 : 0)
                pass("lookColour", [img, k1, k2])
            case "clarity":
                let base = blur(luma(perceptual: true), sigma: r.k("clarity", "radiusFraction", 0.02) * longEdge)
                let k = CIVector(x: look.clarity * r.k("clarity", "amountPerUnit", 0.01), y: r.k("clarity", "midtonePower", 2), z: 0, w: 0)
                pass("lookClarity", [img, base, k, gam, lum])
            case "sharpen":
                let base = blur(luma(perceptual: true), sigma: LookMath.sharpenRadius(longEdge: longEdge, r))
                let k = CIVector(x: look.sharpen * r.k("sharpen", "amountPerUnit", 0.01), y: max(1e-6, r.k("sharpen", "threshold", 0.01)), z: 0, w: 0)
                pass("lookSharpen", [img, base, k, gam, lum])
            case "vignette":
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

    /// The crop and straighten alone (the canvas bakes them into its `base`, then applies the
    /// look with `crop: false`).
    func geometry(_ img: CIImage, _ c: Look.Crop?) -> CIImage { c.map { cropped(img, $0) } ?? img }

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

/// `CIRAWFilter.linearSpaceFilter` for the lens shading: the frame times the radial gain.
nonisolated final class LookShadingFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    private let shading: LookLensShading
    private let amount: Double

    init(shading: LookLensShading, amount: Double) {
        self.shading = shading
        self.amount = amount
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override var outputImage: CIImage? {
        guard let img = inputImage else { return nil }
        guard let gain = LookPipeline.shadingGain(shading, amount: amount, extent: img.extent) else { return img }
        return gain.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: img.extent)
    }
}
