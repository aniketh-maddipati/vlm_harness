import CoreImage
import Foundation

/// The Edit look, native. The page describes a look as the CSS filter string that
/// `LuminaCore.editFilter(r)` returns (`brightness(…) contrast(…) sepia(…)|hue-rotate(…) [blur(…)]`).
/// That string is the contract: this parses it and applies the Filter Effects spec maths, so a
/// RAW export or 100 % view looks like what Edit showed (ANSWERS-phase0 §3, ΔE < 1 vs WebKit).
nonisolated enum SetsEditLook {
    enum Op: Equatable {
        case brightness(Double), contrast(Double), sepia(Double), hueRotate(degrees: Double), saturate(Double), blur(Double)
    }

    /// Which values the matrices act on. Measured (Tests/probe look-parity): WebKit applies CSS
    /// filter functions to sRGB-encoded values — mean ΔE 0.4–0.6 vs 3.5–8.4 for linear. The rest is
    /// WebKit's 8-bit fixed-point filter path (brightness 1.231 lands as floor(v·315/256)).
    enum Space { case sRGB, linear }


    struct ParseError: Error, CustomStringConvertible { let description: String }

    static func parse(_ css: String) throws -> [Op] {
        let s = css.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "none" { return [] }
        var ops: [Op] = []
        let rx = try NSRegularExpression(pattern: #"([a-z-]+)\(\s*(-?[0-9.]+)\s*(deg|px|%)?\s*\)"#)
        let ns = s as NSString
        var covered = 0
        for m in rx.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            covered += m.range.length
            let name = ns.substring(with: m.range(at: 1))
            var v = Double(ns.substring(with: m.range(at: 2))) ?? 0
            if m.range(at: 3).location != NSNotFound, ns.substring(with: m.range(at: 3)) == "%" { v /= 100 }
            switch name {
            case "brightness": ops.append(.brightness(v))
            case "contrast": ops.append(.contrast(v))
            case "sepia": ops.append(.sepia(min(1, max(0, v))))
            case "hue-rotate": ops.append(.hueRotate(degrees: v))
            case "saturate": ops.append(.saturate(v))
            case "blur": ops.append(.blur(v))
            default: throw ParseError(description: "unsupported filter function \(name) in '\(css)'")
            }
        }
        let spaces = s.filter { $0 == " " }.count
        if covered + spaces < ns.length { throw ParseError(description: "couldn't read filter '\(css)'") }
        return ops
    }

    /// Row-major 3×3 colour matrix plus offset for one op (Filter Effects Module Level 1, §13.2).
    static func matrix(_ op: Op) -> (m: [Double], bias: Double)? {
        switch op {
        case .brightness(let b):
            return ([b, 0, 0, 0, b, 0, 0, 0, b], 0)
        case .contrast(let c):
            return ([c, 0, 0, 0, c, 0, 0, 0, c], 0.5 - 0.5 * c)
        case .sepia(let a):
            let k = 1 - a
            return ([0.393 + 0.607 * k, 0.769 - 0.769 * k, 0.189 - 0.189 * k,
                     0.349 - 0.349 * k, 0.686 + 0.314 * k, 0.168 - 0.168 * k,
                     0.272 - 0.272 * k, 0.534 - 0.534 * k, 0.131 + 0.869 * k], 0)
        case .hueRotate(let deg):
            let r = deg * .pi / 180, c = cos(r), s = sin(r)
            return ([0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928,
                     0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283,
                     0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072], 0)
        case .saturate(let v):
            return ([0.213 + 0.787 * v, 0.715 - 0.715 * v, 0.072 - 0.072 * v,
                     0.213 - 0.213 * v, 0.715 + 0.285 * v, 0.072 - 0.072 * v,
                     0.213 - 0.213 * v, 0.715 - 0.715 * v, 0.072 + 0.928 * v], 0)
        case .blur:
            return nil
        }
    }

    /// Applies the look. Each function clamps to [0, 1] like the browser's filter chain does.
    static func apply(_ ops: [Op], to input: CIImage, space: Space = .sRGB) -> CIImage {
        guard !ops.isEmpty else { return input }
        var img = space == .sRGB ? input.applyingFilter("CILinearToSRGBToneCurve") : input
        for op in ops {
            if case .blur(let px) = op {
                if px > 0 { img = img.clampedToExtent().applyingGaussianBlur(sigma: px).cropped(to: input.extent) }
                continue
            }
            guard let (m, bias) = matrix(op) else { continue }
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: m[0], y: m[1], z: m[2], w: 0),
                "inputGVector": CIVector(x: m[3], y: m[4], z: m[5], w: 0),
                "inputBVector": CIVector(x: m[6], y: m[7], z: m[8], w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
            ]).applyingFilter("CIColorClamp")
        }
        return space == .sRGB ? img.applyingFilter("CISRGBToneCurveToLinear") : img
    }

    // MARK: RAW render

    static let context = CIContext(options: [.cacheIntermediates: false])

    /// RAW → default Core Image RAW settings (no auto) → the look → sRGB JPEG, quality 0.9 like the
    /// page's canvas export. `px == "2048"` scales so the width is at most 2048 (the page's rule).
    static func renderJPEG(raw url: URL, css: String, px: String) throws -> Data {
        guard let raw = CIRAWFilter(imageURL: url) else { throw ParseError(description: "not a RAW file Core Image can read: \(url.lastPathComponent)") }
        guard var img = raw.outputImage else { throw ParseError(description: "couldn't decode \(url.lastPathComponent)") }
        if px == "2048", img.extent.width > 2048 {
            let s = 2048 / img.extent.width
            img = img.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: s, kCIInputAspectRatioKey: 1])
        }
        img = apply(try parse(css), to: img)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let jpg = context.jpegRepresentation(of: img, colorSpace: srgb,
                                                    options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.9])
        else { throw ParseError(description: "JPEG encode failed for \(url.lastPathComponent)") }
        return jpg
    }
}
