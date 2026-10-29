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
        /// The photo's tone anchor (log-mean luma of the whole developed frame): Highlights and
        /// Shadows act relative to it. The same number for every size, tier and crop of a photo.
        let anchor: LookMath.ToneAnchor
        /// The photo's automatic masks, placed on this image: what a look's `mask:` tokens blend
        /// through. Nil (no masks known) renders the look without them.
        var masks: PhotoMasks? = nil
        /// The Creative Style the camera shot with (`LookCameraStyle`), for the camera profile.
        /// Nil for anything not read from a Sony RAW (the embedded JPEG already is the camera's look).
        var style: String? = nil
        var extent: CGRect { image.extent }
        var longEdge: CGFloat { max(image.extent.width, image.extent.height) }

        /// The same image with `found` as its masks, the image being the whole upright photo (a
        /// develop, a preview, an export): the photo's top left is the image's top left.
        func withMasks(_ found: [LookMasks.Found]?, key: String) -> Developed {
            var d = self
            d.masks = found.map { PhotoMasks(key: key, found: $0, toImage: LookPipeline.frameTransform(image.extent)) }
            return d
        }
    }

    /// A photo's automatic masks as one image sees them (`Look.locals`, DESIGN-ASKS Prompt 29): the
    /// outlines `SetsMasks` found (`LookMasks.Found.outline`: fractions of the upright photo from
    /// its top left, before crop and turn) and `toImage`, where a point of the photo lands in this
    /// image (Core Image pixels, y up). Whatever makes an image from a photo, or moves one (the
    /// geometry, a scale, a tile's place, a turn), moves `toImage` with it, so a mask stays on the
    /// same content in the canvas's bases, the loupe's tiles, a preview and the export alike.
    struct PhotoMasks: @unchecked Sendable {
        /// What the raster cache knows these outlines by (`key(rel:_:)`).
        let key: String
        let found: [LookMasks.Found]
        var toImage: CGAffineTransform

        /// After `toImage`, `t` (the image moved by it).
        func placed(_ t: CGAffineTransform) -> PhotoMasks {
            var m = self
            m.toImage = toImage.concatenating(t)
            return m
        }

        /// The photo, then `t`: for outlines placed by a transform from photo fractions.
        func placed(photo t: CGAffineTransform) -> PhotoMasks {
            var m = self
            m.toImage = t
            return m
        }

        /// The photo's path and a digest of what was found in it: two findings of one photo with
        /// different outlines never share a raster.
        static func key(rel: String, _ found: [LookMasks.Found]) -> String {
            var h = Hasher()
            for f in found {
                h.combine(f.id)
                for loop in f.outline { h.combine(loop.count); for p in loop { h.combine(p.x); h.combine(p.y) } }
            }
            return "\(rel)#\(found.count)#\(h.finalize())"
        }
    }

    /// Photo fractions (0 … 1 from the top left) → pixels of an upright image covering `rect`
    /// (Core Image, y up): (u, v) → (minX + u·w, maxY − v·h).
    static func frameTransform(_ rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(a: rect.width, b: 0, c: 0, d: -rect.height, tx: rect.minX, ty: rect.maxY)
    }

    /// The transform that lays rect `a` onto rect `b` (a scale and a move, no flip).
    static func mapping(from a: CGRect, to b: CGRect) -> CGAffineTransform {
        guard a.width > 0, a.height > 0, !a.isInfinite, !b.isInfinite else { return .identity }
        return CGAffineTransform(a: b.width / a.width, b: 0, c: 0, d: b.height / a.height, tx: b.minX - a.minX * b.width / a.width, ty: b.minY - a.minY * b.height / a.height)
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
    /// default), `nr` is the look's Detail ▸ luminance noise reduction (0 … 100). `dust` lifts out
    /// the sensor dust `LookDust.Registry` holds for the file (the look's `dust:1`).
    static func develop(url: URL, longEdge px: Int?, rules: LookRules, decoderVersion: Int? = nil, nr: Double? = nil, dust: Bool = false) throws -> Developed {
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
        let lens = shading > 0 ? LookLensShading.read(url: url).flatMap { $0.corrects ? $0 : nil } : nil
        // Dust lives on the sensor, so it is lifted with the frame as stored: the decoder is told not
        // to turn the picture, and it is turned here after (where its linear stage runs is then moot).
        let spots = dust ? LookDust.Registry.shared.spots(for: url) : []
        let turn = raw.orientation
        if !spots.isEmpty { raw.orientation = .up }
        if lens != nil || !spots.isEmpty { raw.linearSpaceFilter = LookShadingFilter(shading: lens, amount: shading, dust: spots) }
        guard var out = raw.outputImage, !out.extent.isEmpty, !out.extent.isInfinite else { throw Failure("couldn't decode \(url.lastPathComponent)") }
        if !spots.isEmpty, turn != .up { out = out.oriented(turn) }
        let asShot = Look.WhiteBalance(kelvin: Double(raw.neutralTemperature), tint: Double(raw.neutralTint))
        return Developed(image: try baseMatched(Self.atOrigin(out), rules: rules), asShot: asShot, anchor: toneAnchor(raw: url, rules: rules),
                         style: LookCameraStyle.read(url: url))
    }

    // MARK: the tone anchor

    nonisolated(unsafe) private static var anchors: [String: LookMath.ToneAnchor] = [:]
    nonisolated(unsafe) private static var anchorContexts: [String: CIContext] = [:]
    private static let anchorLock = NSLock()
    static let anchorPx = 256
    /// For images developed without rules (a JPEG, the embedded preview): the rules' own defaults.
    static let defaultWorkingSpace = "extendedLinearSRGB"
    static let defaultLuma = [0.2126, 0.7152, 0.0722]

    /// A RAW's tone anchor: the log-mean luma of its whole frame, developed small (256 px, the
    /// default decoder, the same shading and base match) and measured once per file and rules. The
    /// canvas, the loupe's tiles and the export all get this one number, whatever their size or
    /// decoder, so Highlights and Shadows render the same in all three.
    static func toneAnchor(raw url: URL, rules: LookRules) -> LookMath.ToneAnchor {
        let coefficients = (rules.stages["rawDevelop"]?.coefficients ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])).map { "\($0.contentModificationDate?.timeIntervalSince1970 ?? 0)|\($0.fileSize ?? 0)" } ?? ""
        let key = "raw|\(url.path)|\(stamp)|\(coefficients)|\(rules.workingSpace)"
        if let a = anchorLock.withLock({ anchors[key] }) { return a }
        guard let raw = CIRAWFilter(imageURL: url) else { return .reference }
        let long = max(raw.nativeSize.width, raw.nativeSize.height)
        if long > CGFloat(anchorPx) { raw.scaleFactor = Float(CGFloat(anchorPx) / long) }
        raw.boostAmount = Float(rules.k("rawDevelop", "boostAmount", 1))
        let shading = rules.k("rawDevelop", "lensShading", 0)
        if shading > 0, let s = LookLensShading.read(url: url), s.corrects { raw.linearSpaceFilter = LookShadingFilter(shading: s, amount: shading) }
        guard let out = raw.outputImage, !out.extent.isEmpty, !out.extent.isInfinite, let img = try? baseMatched(atOrigin(out), rules: rules) else { return .reference }
        return toneAnchor(of: img, key: key, workingSpace: rules.workingSpace, luma: rules.luma)
    }

    /// The log-mean luma of `img` (scaled to at most 256 px), remembered under `key`.
    static func toneAnchor(of img: CIImage, key: String, workingSpace: String, luma: [Double]) -> LookMath.ToneAnchor {
        if let a = anchorLock.withLock({ anchors[key] }) { return a }
        let small = atOrigin(scaled(img, longEdge: anchorPx))
        let w = Int(small.extent.width.rounded(.down)), h = Int(small.extent.height.rounded(.down))
        guard w > 0, h > 0, !small.extent.isInfinite, let space = colorSpace(named: workingSpace) else { return .reference }
        let ctx: CIContext = anchorLock.withLock {
            if let c = anchorContexts[workingSpace] { return c }
            let c = CIContext(options: [.workingColorSpace: space, .workingFormat: CIFormat.RGBAh.rawValue, .cacheIntermediates: false, .name: "LookPipeline.anchor"])
            anchorContexts[workingSpace] = c
            return c
        }
        var px = [Float](repeating: 0, count: w * h * 4)
        ctx.render(small, toBitmap: &px, rowBytes: w * 16, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: space)
        let a = LookMath.toneAnchor(pixels: px, luma: luma)
        anchorLock.withLock { anchors[key] = a; if anchors.count > 4096 { anchors.removeAll(); anchors[key] = a } }
        return a
    }

    /// The decoder's rendering brought to Lightroom's default (`LookMath.baseMatch`), as the last
    /// step of rawDevelop: every base, tile and export starts from the same matched picture.
    static func baseMatched(_ img: CIImage, rules: LookRules) throws -> CIImage {
        let m = LookMath.BaseMatch(rules)
        guard !m.isIdentity else { return img }
        guard let out = try LookKernels.shared().apply("lookBase", extent: img.extent, baseArgs(img, m, rules)) else { throw Failure("base match failed") }
        return out
    }

    /// `lookBase`'s arguments for one base match (rawDevelop's, or the camera profile's).
    static func baseArgs(_ img: CIImage, _ m: LookMath.BaseMatch, _ rules: LookRules) -> [Any] {
        let w = m.rows, lum = rules.luma
        return [img, CIVector(x: w[0][0], y: w[0][1], z: w[0][2], w: 0), CIVector(x: w[1][0], y: w[1][1], z: w[1][2], w: 0),
                CIVector(x: w[2][0], y: w[2][1], z: w[2][2], w: 0),
                CIVector(x: m.lift, y: m.s, z: 1 / rules.perceptualGamma, w: rules.perceptualGamma),
                CIVector(x: lum[0], y: lum[1], z: lum[2], w: 0),
                CIVector(x: m.hiDesat, y: m.hiFrom, z: m.loDesat, w: m.loBelow)]
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

    /// Each dust spot's gain (`LookDust.patch`) as a small opaque image placed over its box in
    /// `extent` (the frame as stored, top row first in the patch, Core Image's origin at the bottom).
    /// Each is multiplied onto the frame inside its box only; elsewhere the frame is left as it is.
    static func dustGain(_ spots: [LookDust.Spot], extent: CGRect) -> [CIImage] {
        guard !spots.isEmpty, !extent.isInfinite, extent.width >= 1, extent.height >= 1 else { return [] }
        let w = Int(extent.width.rounded()), h = Int(extent.height.rounded())
        return spots.compactMap { spot in
            guard let p = LookDust.patch(spot, width: w, height: h) else { return nil }
            var px = [Float](repeating: 1, count: p.width * p.height * 4)
            // A bitmap's first row is its top, as in the patch.
            for j in 0..<(p.width * p.height) { let g = p.gain[j]; px[4 * j] = g; px[4 * j + 1] = g; px[4 * j + 2] = g }
            let data = px.withUnsafeBufferPointer { Data(buffer: $0) }
            return CIImage(bitmapData: data, bytesPerRow: p.width * 16, size: CGSize(width: p.width, height: p.height), format: .RGBAf, colorSpace: nil)
                .transformed(by: CGAffineTransform(translationX: extent.minX + CGFloat(p.x0), y: extent.maxY - CGFloat(p.y0 + p.height)))
        }
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
        let upright = Self.atOrigin(img)
        return Developed(image: Self.scaled(upright, longEdge: px), asShot: Look.WhiteBalance(kelvin: 5500, tint: 0),
                         anchor: toneAnchor(of: upright, key: "preview|\(url.path)|\(offset)|\(length)", workingSpace: defaultWorkingSpace, luma: defaultLuma))
    }

    /// Any image ImageIO reads (JPEG, TIFF, PNG): for tests, the A/B page and fixtures without
    /// RAWs. Orientation applied, scaled to `longEdge` with Lanczos. As-shot is taken as D55 / 0.
    static func developImage(url: URL, longEdge px: Int?) throws -> Developed {
        guard let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw Failure("can't read \(url.lastPathComponent)") }
        let upright = Self.atOrigin(img)
        return Developed(image: Self.scaled(upright, longEdge: px), asShot: Look.WhiteBalance(kelvin: 5500, tint: 0),
                         anchor: toneAnchor(of: upright, key: "image|\(url.path)", workingSpace: defaultWorkingSpace, luma: defaultLuma))
    }

    /// A RAW when Core Image reads it as one, else any image ImageIO reads.
    static func developAny(url: URL, longEdge px: Int?, rules: LookRules, decoderVersion: Int? = nil, nr: Double? = nil, dust: Bool = false) throws -> Developed {
        if isRAW(url) { return try develop(url: url, longEdge: px, rules: rules, decoderVersion: decoderVersion, nr: nr, dust: dust) }
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
    ///
    /// Then the adjustments inside a mask (`Look.locals`), in order: the same stages with the
    /// mask's values, on the picture the global look made, blended into it through the mask
    /// (`maskImage`). A mask `dev` does not carry (no masks found yet, another id) is left out:
    /// the render is the look without it, never a failure.
    func apply(_ look: Look, to dev: Developed, crop: Bool = true) -> CIImage {
        var img = dev.image
        var masks = dev.masks
        if crop {
            let g = geometryPlaced(img, look.crop, rot: look.rot)
            img = g.image
            masks = masks?.placed(g.transform)
        }
        var anchor = dev.anchor
        img = stages(look, on: img, asShot: dev.asShot, style: dev.style, anchor: &anchor)
        guard !look.locals.isEmpty, let masks else { return img }
        let extent = img.extent
        for local in look.locals {
            guard !local.isNeutral, let found = masks.found.first(where: { $0.id == local.mask }),
                  let mask = maskImage(found, masks, extent: extent) else { continue }
            // The mask's own exposure moves its own copy of the anchor, as the global one does.
            var a = anchor
            let adjusted = stages(local.look, on: img, asShot: dev.asShot, style: dev.style, anchor: &a)
            img = adjusted.applyingFilter("CIBlendWithRedMask", parameters: [kCIInputBackgroundImageKey: img, kCIInputMaskImageKey: mask]).cropped(to: extent)
        }
        return img
    }

    /// The look's stages on `input` (its extent is the frame the stages see: the blurs' radii and
    /// the vignette follow it), in the rules' order, the ones at reset left out. `anchor` comes
    /// back moved by the exposure stage. The global look and each mask's run through here.
    private func stages(_ look: Look, on input: CIImage, asShot: Look.WhiteBalance, style: String?, anchor: inout LookMath.ToneAnchor) -> CIImage {
        var img = input
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
            case "camera":
                // The camera's look for the photo's Creative Style, the base match's form with the
                // style's numbers. Nothing without a style: an embedded JPEG already is the camera's look.
                guard style != nil, let m = LookMath.BaseMatch(camera: style, r), !m.isIdentity else { continue }
                pass("lookBase", Self.baseArgs(img, m, r))
            case "exposure":
                let g = LookMath.exposureGain(look.ev, r), w = LookMath.exposureWhite(r)
                pass("lookExposure", [img, CIVector(x: g, y: w)])
                anchor.mean = LookMath.exposure(anchor.mean, gain: g, white: w)
                anchor.high = anchor.high.map { LookMath.exposure($0, gain: g, white: w) }
            case "whiteBalance":
                let g = LookMath.whiteBalanceGains(look.wb, asShot: asShot, r)
                pass("lookWhiteBalance", [img, CIVector(x: g.r, y: g.g, z: g.b, w: 1), CIVector(x: LookMath.whiteBalanceWhite(r), y: 0)])
            case "whitesBlacks":
                let wbk = CIVector(x: look.whites * r.k("whitesBlacks", "whitesPerUnit", 0.003),
                                   y: -look.blacks * r.k("whitesBlacks", "blacksPerUnit", 0.002),
                                   z: r.k("whitesBlacks", "whitesPower", 2), w: r.k("whitesBlacks", "blacksPower", 2))
                pass("lookPre", [img, ones, wbk, gam])
            case "tone":
                let base = blur(luma(perceptual: false), sigma: r.k("tone", "radiusFraction", 0.03) * longEdge)
                let n = LookMath.toneNormalisers(anchor: anchor, r)
                let sh = CIVector(x: look.shadows * r.k("tone", "shadowsStopsPerUnit", 0.01) * n.shadowsGain, y: r.k("tone", "shadowsTau", 0.2), z: n.shadows, w: n.highlights)
                let hl = CIVector(x: look.highlights * r.k("tone", "highlightsStopsPerUnit", 0.01) * n.highlightsGain, y: r.k("tone", "highlightsKnee", 0.7), z: LookMath.toneWhite(r), w: r.k("tone", "detailGain", 1))
                pass("lookTone", [img, base, sh, hl, gam, lum])
            case "contrast":
                let k = CIVector(x: min(0.95, max(0.05, r.k("contrast", "midpoint", 0.46))),
                                 y: exp2(look.contrast * r.k("contrast", "slopePerUnit", 0.006)),
                                 z: min(1, max(0, r.k("contrast", "lumaMix", 0.5))), w: 0)
                pass("lookContrast", [img, k, gam, lum])
            case "curve":
                let lut = curveTable(look.curve)
                let k = CIVector(x: 1 / r.perceptualGamma, y: r.perceptualGamma, z: Double(LookMath.curveNodes - 1), w: 0)
                if let out = kernels.apply("lookCurve", extent: extent, table: lut, [img, lut, k]) { img = out }
            case "colour":
                let up = r.k("colour", "vibrancePerUnit", 0.01)
                let k1 = CIVector(x: max(0, 1 + look.saturation * r.k("colour", "saturationPerUnit", 0.01)),
                                  y: look.vibrance * (look.vibrance > 0 ? up : r.k("colour", "vibranceDownPerUnit", up)),
                                  z: max(1e-6, r.k("colour", "vibranceChromaMax", 0.25)),
                                  w: 1 - min(1, max(0, r.k("colour", "vibranceFloor", 0))))
                let k2 = CIVector(x: r.k("colour", "skinHue", 60), y: max(1e-6, r.k("colour", "skinWidth", 25)),
                                  z: look.vibrance > 0 ? r.k("colour", "skinProtect", 0.7) : 0, w: look.bw ? 1 : 0)
                pass("lookColour", [img, k1, k2])
            case "mixer":
                let c = LookMath.mixerCentres(r), m = look.mixer
                func pair(_ v: [Double], _ scale: Double) -> [CIVector] {
                    [CIVector(x: v[0] * scale, y: v[1] * scale, z: v[2] * scale, w: v[3] * scale), CIVector(x: v[4] * scale, y: v[5] * scale, z: v[6] * scale, w: v[7] * scale)]
                }
                pass("lookMixer", [img] + pair(c, 1) + pair(m.hue, r.k("mixer", "hueDegreesPerUnit", 0.3)) + pair(m.saturation, r.k("mixer", "saturationPerUnit", 0.01))
                     + pair(m.luminance, r.k("mixer", "luminancePerUnit", 0.003)) + [CIVector(x: max(1e-6, r.k("mixer", "luminanceChromaKnee", 0.05)), y: 0, z: 0, w: 0)])
            case "clarity":
                let base = blur(luma(perceptual: true), sigma: r.k("clarity", "radiusFraction", 0.02) * longEdge)
                let k = CIVector(x: look.clarity * r.k("clarity", "amountPerUnit", 0.01), y: r.k("clarity", "midtonePower", 2), z: 0, w: 0)
                pass("lookClarity", [img, base, k, gam, lum])
            case "sharpen":
                let base = blur(luma(perceptual: true), sigma: LookMath.sharpenRadius(longEdge: longEdge, r))
                let k = CIVector(x: look.sharpen * r.k("sharpen", "amountPerUnit", 0.01), y: max(1e-6, r.k("sharpen", "threshold", 0.01)), z: 0, w: 0)
                pass("lookSharpen", [img, base, k, gam, lum])
            case "vignette":
                let f = LookMath.VignetteForm(shape: look.vignetteShape, vignette: look.vignette, aspect: extent.height > 0 ? extent.width / extent.height : 1, r)
                let k = CIVector(x: look.vignette * f.stopsPerUnit, y: f.edge0, z: f.edge1, w: f.keep)
                let sh = CIVector(x: extent.width > 0 ? f.sx * 2 / extent.width : 0, y: extent.height > 0 ? f.sy * 2 / extent.height : 0, z: f.power, w: f.norm)
                pass("lookVignette", [img, k, sh, CIVector(x: f.keepPower, y: 1 / r.perceptualGamma, z: 0, w: 0), lum, CIVector(x: extent.midX, y: extent.midY)])
            default:
                continue
            }
        }
        // Sky blue (LookSky's `blu`, only inside a mask): after the rules' stages, outside the rules'
        // order, so rules-v1.json and every look without it are untouched.
        if look.skyBlue != 0 {
            typealias S = LookMath.SkyBlue
            pass("lookSkyBlue", [img, CIVector(x: min(1, max(0, look.skyBlue / 100)), y: S.hue, z: S.capShare, w: 0),
                                 CIVector(x: S.cuspL, y: S.cuspC, z: S.turnFull, w: S.turnNone), CIVector(x: S.greyFull, y: S.greyNone, z: 0, w: 0)])
        }
        return img
    }

    // MARK: the tone curve's table

    private let curveLock = NSLock()
    private var lastCurve: (curve: Look.ToneCurve, table: CIImage)?

    /// `LookMath.curveTables` as an image the `lookCurve` kernel reads: `curveNodes` × 1 px, the
    /// three channels' tables in r, g, b, raw floats (no colour space, read at texel centres).
    /// The last curve's image is kept: while another slider moves, the curve's table is the
    /// same image and Core Image does not upload it again.
    func curveTable(_ curve: Look.ToneCurve) -> CIImage {
        if let hit = curveLock.withLock({ lastCurve?.curve == curve ? lastCurve?.table : nil }) { return hit }
        let t = LookMath.curveTables(curve, rules), n = LookMath.curveNodes
        var px = [Float](repeating: 1, count: 4 * n)
        for i in 0..<n { px[4 * i] = Float(t.r[i]); px[4 * i + 1] = Float(t.g[i]); px[4 * i + 2] = Float(t.b[i]) }
        let img = CIImage(bitmapData: px.withUnsafeBufferPointer { Data(buffer: $0) }, bytesPerRow: 16 * n, size: CGSize(width: n, height: 1), format: .RGBAf, colorSpace: nil)
            .samplingNearest()
        curveLock.withLock { lastCurve = (curve, img) }
        return img
    }

    // MARK: masks (adjustments inside a mask)

    /// How far a mask's edge is softened, as a fraction of the photo's long edge: about 12 px of
    /// a 2048 px raster, the same share of the photo on the canvas, a tile and the export.
    static let maskFeather = 0.006
    private static let maskRasters = 48
    private let maskLock = NSLock()
    private var maskCache: [String: CIImage] = [:]
    private var maskOrder: [String] = []

    /// `found`'s outline as a mask over `extent` of an image `masks` is placed on: 1 inside, 0
    /// outside, antialiased and feathered (`LookMasks.raster`), sampled through `toImage`, so any
    /// crop, straighten, turn, scale or tile lines up. Nil when the photo is not a usable size in
    /// this image (a degenerate transform).
    ///
    /// The raster is made in the photo's own frame at one of a few sizes chosen from how large
    /// the photo is in this image (`LookMasks.rasterSize`) and kept (one-channel, 8 bit, a few MB
    /// at most): a slider moving inside a mask reuses it on every frame.
    func maskImage(_ found: LookMasks.Found, _ masks: PhotoMasks, extent: CGRect) -> CIImage? {
        let t = masks.toImage
        // How many pixels of this image the whole photo spans, across and down.
        let pw = (t.a * t.a + t.b * t.b).squareRoot(), ph = (t.c * t.c + t.d * t.d).squareRoot()
        guard pw.isFinite, ph.isFinite, pw >= 1, ph >= 1, !extent.isEmpty, !extent.isInfinite else { return nil }
        guard let plane = maskRaster(found, key: masks.key, photo: CGSize(width: pw, height: ph)) else { return nil }
        let w = plane.extent.width, h = plane.extent.height
        // Raster pixels (Core Image, y up: its first row is the photo's top) → photo fractions → this image.
        let toPhoto = CGAffineTransform(a: 1 / w, b: 0, c: 0, d: -1 / h, tx: 0, ty: 1)
        return plane.clampedToExtent().transformed(by: toPhoto.concatenating(t)).cropped(to: extent)
    }

    /// The raster for a photo that is `photo` pixels in the image asking (cached).
    func maskRaster(_ found: LookMasks.Found, key: String, photo: CGSize) -> CIImage? {
        let size = LookMasks.rasterSize(photo: Double(photo.width), Double(photo.height))
        let k = "\(key)|\(found.id)|\(size.width)x\(size.height)"
        if let hit = maskLock.withLock({ maskCache[k] }) { return hit }
        let plane = LookMasks.raster(found.outline, width: size.width, height: size.height, feather: Self.maskFeather)
        guard !plane.isEmpty else { return nil }
        let bytes = Data(plane.values.map { UInt8((min(1, max(0, $0)) * 255).rounded()) })
        let img = CIImage(bitmapData: bytes, bytesPerRow: size.width, size: CGSize(width: size.width, height: size.height), format: .R8, colorSpace: nil)
        maskLock.withLock {
            if maskCache.updateValue(img, forKey: k) == nil { maskOrder.append(k) }
            while maskOrder.count > Self.maskRasters { maskCache.removeValue(forKey: maskOrder.removeFirst()) }
        }
        return img
    }

    /// The rasters `look`'s masks need on an image `masks` is placed on, made now (off the main
    /// thread: the canvas calls this before it draws the first frame with them).
    func prepareMasks(_ look: Look, _ masks: PhotoMasks) {
        let t = masks.toImage
        let photo = CGSize(width: (t.a * t.a + t.b * t.b).squareRoot(), height: (t.c * t.c + t.d * t.d).squareRoot())
        guard photo.width >= 1, photo.height >= 1, photo.width.isFinite, photo.height.isFinite else { return }
        for local in look.locals { if let f = masks.found.first(where: { $0.id == local.mask }) { _ = maskRaster(f, key: masks.key, photo: photo) } }
    }

    /// The geometry alone: crop and straighten in the frame as shot, then the quarter turn
    /// (`Look.rot`). The canvas bakes it into its `base`, then applies the look with `crop: false`;
    /// previews and exports get it from `apply`. One function for all of them, so they agree.
    func geometry(_ img: CIImage, _ c: Look.Crop?, rot: Int = 0) -> CIImage {
        geometryPlaced(img, c, rot: rot).image
    }

    /// `geometry`, and where a point of `img` lands in its result (Core Image pixels to Core Image
    /// pixels): the masks of a photo follow its picture through the crop, the straighten and the
    /// turn with this (`PhotoMasks.placed`).
    func geometryPlaced(_ img: CIImage, _ c: Look.Crop?, rot: Int = 0) -> (image: CIImage, transform: CGAffineTransform) {
        let cut = c.map { croppedPlaced(img, $0) } ?? (img, .identity)
        let turn = Self.turnedPlaced(cut.image, rot: rot)
        return (turn.image, cut.transform.concatenating(turn.transform))
    }

    /// The transform that turns a frame of `size` clockwise by `rot` degrees (a multiple of 90)
    /// and leaves it at the origin, in Core Image's coordinates (y up). A point of the frame
    /// lands where it is in the turned picture, so a part of the frame (a region tile's
    /// composite) turns with the same transform as the whole.
    static func turnTransform(size: CGSize, rot: Int) -> CGAffineTransform {
        switch ((rot % 360) + 360) % 360 {
        case 90: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.width)                  // (x, y) → (y, W − x)
        case 180: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: size.width, ty: size.height)      // (x, y) → (W − x, H − y)
        case 270: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.height, ty: 0)                // (x, y) → (H − y, x)
        default: return .identity
        }
    }

    /// `img` (origin at 0, 0) turned clockwise by `rot` degrees. 0 is the image itself.
    static func turned(_ img: CIImage, rot: Int) -> CIImage { turnedPlaced(img, rot: rot).image }

    /// `turned`, and the transform it moved the picture by.
    static func turnedPlaced(_ img: CIImage, rot: Int) -> (image: CIImage, transform: CGAffineTransform) {
        guard ((rot % 360) + 360) % 360 != 0, !img.extent.isInfinite else { return (img, .identity) }
        let turn = turnTransform(size: img.extent.size, rot: rot)
        return atOriginPlaced(img.transformed(by: turn), after: turn)
    }

    /// `atOrigin`, with the transform so far (`after`) and the move it adds.
    static func atOriginPlaced(_ img: CIImage, after t: CGAffineTransform = .identity) -> (image: CIImage, transform: CGAffineTransform) {
        let e = img.extent
        guard e.origin != .zero, !e.isInfinite else { return (img, t) }
        return (atOrigin(img), t.concatenating(CGAffineTransform(translationX: -e.origin.x, y: -e.origin.y)))
    }

    /// Straighten about the centre, then the box as fractions of the frame (y from the top); and
    /// the transform the picture moved by.
    private func croppedPlaced(_ img: CIImage, _ c: Look.Crop) -> (image: CIImage, transform: CGAffineTransform) {
        let e = img.extent
        var out = img
        var t = CGAffineTransform.identity
        if c.rotate != 0 {
            t = CGAffineTransform(translationX: e.midX, y: e.midY).rotated(by: -c.rotate * .pi / 180).translatedBy(x: -e.midX, y: -e.midY)
            out = out.transformed(by: t)
        }
        let rect = CGRect(x: e.minX + c.x * e.width, y: e.minY + (1 - c.y - c.h) * e.height, width: c.w * e.width, height: c.h * e.height).integral
        return Self.atOriginPlaced(out.cropped(to: rect), after: t)
    }

    // MARK: outputTransform

    /// Brought into 0…1 in the working space by the rules' mapper (`LookRules.mapper`): the clamp,
    /// or `LookMath.DisplayMapper`. The colour space conversion happens in the encode.
    func output(_ img: CIImage) -> CIImage {
        guard rules.mapper == .sigmoid else { return img.applyingFilter("CIColorClamp") }
        let m = LookMath.DisplayMapper(rules), r = m.insetRows, o = m.outsetRows
        var args: [Any] = [img]
        for row in r + o { args.append(CIVector(x: row[0], y: row[1], z: row[2], w: 0)) }
        args.append(CIVector(x: m.kneeEV, y: m.maxEV, z: m.headroom, w: m.hueKeep))
        return kernels.apply("lookDisplay", extent: img.extent, args) ?? img.applyingFilter("CIColorClamp")
    }

    func jpeg(_ img: CIImage, quality: Double = 0.9, space: OutputSpace = .sRGB) throws -> Data {
        let q = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        guard let d = context.jpegRepresentation(of: output(img), colorSpace: space.cgColorSpace, options: [q: quality]) else { throw Failure("JPEG encode failed") }
        return d
    }

    /// 16-bit TIFF (RGBA16, the alpha channel is all ones) in `space`, tagged with its profile.
    func tiff16(_ img: CIImage, space: OutputSpace) throws -> Data {
        guard let d = context.tiffRepresentation(of: output(img), format: .RGBA16, colorSpace: space.cgColorSpace, options: [:]) else { throw Failure("TIFF encode failed") }
        return d
    }

    func png(_ img: CIImage, space: OutputSpace = .sRGB) throws -> Data {
        guard let d = context.pngRepresentation(of: output(img), format: .RGBA8, colorSpace: space.cgColorSpace, options: [:]) else { throw Failure("PNG encode failed") }
        return d
    }

    /// Rasterises a developed image once (half floats in the working space) so the look stages
    /// re-run on a bitmap, not on the RAW decode. Returns the image and its size in bytes.
    func rasterised(_ dev: Developed) throws -> (Developed, Int) {
        let e = dev.extent.integral
        guard let cg = context.createCGImage(dev.image, from: e, format: .RGBAh, colorSpace: workingSpace) else { throw Failure("rasterise failed") }
        // The bitmap starts at the extent's origin, the image at (0, 0): the masks move with it.
        var out = Developed(image: CIImage(cgImage: cg), asShot: dev.asShot, anchor: dev.anchor, style: dev.style)
        out.masks = dev.masks?.placed(CGAffineTransform(translationX: -e.minX, y: -e.minY))
        return (out, cg.bytesPerRow * cg.height)
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
        return Developed(image: CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: size, height: size)), asShot: Look.WhiteBalance(kelvin: 5500, tint: 0), anchor: .reference)
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
        return Developed(image: img, asShot: Look.WhiteBalance(kelvin: 5500, tint: 0), anchor: .reference)
    }
}

/// `CIRAWFilter.linearSpaceFilter` for the lens shading and the sensor dust: the frame times the
/// radial gain, then times each dust spot's gain (`LookDust.patch`; the frame must be as stored).
nonisolated final class LookShadingFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    private let shading: LookLensShading?
    private let amount: Double
    private let dust: [LookDust.Spot]

    init(shading: LookLensShading?, amount: Double, dust: [LookDust.Spot] = []) {
        self.shading = shading
        self.amount = amount
        self.dust = dust
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override var outputImage: CIImage? {
        guard var img = inputImage else { return nil }
        let extent = img.extent
        if let shading, let gain = LookPipeline.shadingGain(shading, amount: amount, extent: extent) {
            img = gain.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: extent)
        }
        // Multiply compositing answers only where both images are (the patch's box), so the lifted
        // box goes back over the frame.
        for patch in LookPipeline.dustGain(dust, extent: extent) {
            img = patch.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: patch.extent)
                .composited(over: img).cropped(to: extent)
        }
        return img
    }
}
