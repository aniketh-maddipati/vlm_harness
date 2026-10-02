import CoreImage
import Foundation

/// The stage kernels, as Metal source compiled at first use with `CIKernel.kernels(withMetalString:)`
/// (macOS 14+; it takes `[[ stitchable ]]` kernels only). Source strings, not a `.ci.metal` file,
/// so the app target, the `lumina-render` SwiftPM tool and the probe all build the same kernels
/// with no compiler flags. Each function repeats a `LookMath` formula; `LookPipelineTests`
/// checks the two agree on flat patches.
///
/// Colour kernels only (one output pixel from the same pixel of each input); the blurs that feed
/// `lookTone`, `lookClarity` and `lookSharpen` are Core Image's own `CIGaussianBlur`.
nonisolated final class LookKernels: @unchecked Sendable {
    static let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    static float lk_perc(float x, float invGamma) { return pow(max(0.0f, x), invGamma); }
    static float lk_lin(float p, float gamma) { return pow(max(0.0f, p), gamma); }
    static float lk_smooth(float e0, float e1, float x) {
        if (e1 <= e0) return x >= e1 ? 1.0f : 0.0f;
        float t = clamp((x - e0) / (e1 - e0), 0.0f, 1.0f);
        return t * t * (3.0f - 2.0f * t);
    }
    static float lk_exposure(float x, float g, float w) {
        if (x <= 0.0f) return x * g;
        if (x >= w) return w + (x - w) / g;
        float t = x / w;
        return w * g * t / (1.0f + (g - 1.0f) * t);
    }
    static float lk_cbrt(float x) { return x < 0.0f ? -pow(-x, 1.0f / 3.0f) : pow(x, 1.0f / 3.0f); }
    static float lk_curve(float p, float m, float a) {
        if (p <= 0.0f) return 0.0f;
        if (p >= 1.0f) return p;
        return p < m ? m * pow(p / m, a) : 1.0f - (1.0f - m) * pow((1.0f - p) / (1.0f - m), a);
    }

    // luma (linear), or perceptual luma when invGamma > 0: the images the blurs work on
    [[ stitchable ]] float4 lookLuma(coreimage::sample_t s, float4 lum, float invGamma) {
        float y = dot(s.rgb, lum.rgb);
        if (invGamma > 0.0f) y = lk_perc(y, invGamma);
        return float4(y, y, y, 1.0f);
    }

    // rawDevelop's base match (LookMath.baseMatch): a midtone curve on luma, then a colour mix.
    // r0, r1, r2 = the mix's rows; k = (lift, s, invGamma, gamma); d = (hiDesat, hiFrom, loDesat, loBelow)
    [[ stitchable ]] float4 lookBase(coreimage::sample_t s, float4 r0, float4 r1, float4 r2, float4 k, float4 lum, float4 d) {
        float y = dot(s.rgb, lum.rgb);
        float g = 1.0f;
        if (y > 1e-6f) {
            float p = lk_perc(y, k.z);
            float pc = clamp(p, 0.0f, 1.0f);
            g = lk_lin(p + k.x * p * (1.0f - pc) + k.y * p * (1.0f - pc) * (pc - 0.5f), k.w) / y;
        }
        float3 t = s.rgb * g;
        float3 m = float3(dot(t, r0.rgb), dot(t, r1.rgb), dot(t, r2.rgb));
        if (d.x != 0.0f || d.z != 0.0f) {
            float ym = dot(m, lum.rgb);
            float pc = clamp(lk_perc(ym, k.z), 0.0f, 1.0f);
            float hi = clamp((pc - d.y) / max(1e-3f, 1.0f - d.y), 0.0f, 1.0f);
            float lo = clamp((d.w - pc) / max(1e-3f, d.w), 0.0f, 1.0f);
            float keep = clamp(1.0f - d.x * hi * hi - d.z * lo * lo, 0.0f, 1.0f);
            m = float3(ym) + (m - float3(ym)) * keep;
        }
        return float4(m, s.a);
    }

    // exposure: a scene gain seen through a sigmoid tone curve (LookMath.exposure). k = (gain G, white w)
    [[ stitchable ]] float4 lookExposure(coreimage::sample_t s, float2 k) {
        return float4(lk_exposure(s.r, k.x, k.y), lk_exposure(s.g, k.x, k.y), lk_exposure(s.b, k.x, k.y), s.a);
    }

    // whiteBalance: per-channel scene gains through the tone curve. g = the gains, k = (white, 0)
    [[ stitchable ]] float4 lookWhiteBalance(coreimage::sample_t s, float4 g, float2 k) {
        return float4(lk_exposure(s.r, g.r, k.x), lk_exposure(s.g, g.g, k.x), lk_exposure(s.b, g.b, k.x), s.a);
    }

    // whitesBlacks (wb = ones). wb = per-channel gains;
    // wbk = (whitesAmt, blacksAmt, whitesPower, blacksPower); gam = (invGamma, gamma)
    [[ stitchable ]] float4 lookPre(coreimage::sample_t s, float4 wb, float4 wbk, float2 gam) {
        float3 c = s.rgb * wb.rgb;
        if (wbk.x != 0.0f || wbk.y != 0.0f) {
            float3 p = pow(max(float3(0.0f), c), float3(gam.x));
            float3 pc = clamp(p, 0.0f, 1.0f);
            float3 q = p - wbk.y * pow(1.0f - pc, float3(wbk.w)) + wbk.x * pow(pc, float3(wbk.z));
            c = pow(max(float3(0.0f), q), float3(gam.y));
        }
        return float4(c, s.a);
    }

    // tone: a local exposure through the tone curve (LookMath.toneGain + exposure). base = blurred
    // linear luma. sh = (shadowsStops, tau, shadows normaliser, highlights normaliser) with the
    // normalisers from the photo's anchor; hl = (highlightsStops, knee, white, detailGain)
    [[ stitchable ]] float4 lookTone(coreimage::sample_t s, coreimage::sample_t base, float4 sh, float4 hl, float2 gam, float4 lum) {
        float ps = lk_perc(base.r * sh.z, gam.x);
        float ph = lk_perc(base.r * sh.w, gam.x);
        float g = exp2(sh.x * exp(-ps / max(0.01f, sh.y)) + hl.x * min(1.0f, ph / max(0.01f, hl.y)));
        float d = 1.0f;
        if (fabs(hl.w - 1.0f) > 1e-9f) {
            float y = dot(s.rgb, lum.rgb);
            d = pow(max(1e-6f, y) / max(1e-6f, base.r), hl.w - 1.0f);
        }
        return float4(lk_exposure(s.r * d, g, hl.z), lk_exposure(s.g * d, g, hl.z), lk_exposure(s.b * d, g, hl.z), s.a);
    }

    // contrast: k = (midpoint, slope a, lumaMix, 0)
    [[ stitchable ]] float4 lookContrast(coreimage::sample_t s, float4 k, float2 gam, float4 lum) {
        float3 per = float3(lk_lin(lk_curve(lk_perc(s.r, gam.x), k.x, k.y), gam.y),
                            lk_lin(lk_curve(lk_perc(s.g, gam.x), k.x, k.y), gam.y),
                            lk_lin(lk_curve(lk_perc(s.b, gam.x), k.x, k.y), gam.y));
        float y = dot(s.rgb, lum.rgb);
        float ratio = y > 1e-9f ? lk_lin(lk_curve(lk_perc(y, gam.x), k.x, k.y), gam.y) / y : 1.0f;
        float3 byLuma = s.rgb * ratio;
        return float4(mix(per, byLuma, k.z), s.a);
    }

    // colour: k1 = (satFactor, vibranceAmt, chromaMax, taper = 1 - vibranceFloor), k2 = (skinHue, skinWidth, skinProtect (0 below 0), bw)
    [[ stitchable ]] float4 lookColour(coreimage::sample_t s, float4 k1, float4 k2) {
        float3 c = s.rgb;
        float l = lk_cbrt(0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b);
        float m = lk_cbrt(0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b);
        float sc = lk_cbrt(0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b);
        float L = 0.2104542553f * l + 0.7936177850f * m - 0.0040720468f * sc;
        float A = 1.9779984951f * l - 2.4285922050f * m + 0.4505937099f * sc;
        float B = 0.0259040371f * l + 0.7827717662f * m - 0.8086757660f * sc;
        float C = length(float2(A, B));
        if (C <= 1e-9f) return s;
        float f;
        if (k2.w > 0.5f) { f = 0.0f; }
        else {
            float h = atan2(B, A) * 57.29577951308232f;
            if (h < 0.0f) h += 360.0f;
            float dh = fmod(fabs(h - k2.x), 360.0f);
            if (dh > 180.0f) dh = 360.0f - dh;
            float skin = exp(-pow(dh / max(1e-6f, k2.y), 2.0f));
            float protect = 1.0f - k2.z * skin;
            float vib = max(0.0f, 1.0f + k1.y * (1.0f - k1.w * min(1.0f, C / k1.z)) * protect);
            f = k1.x * vib;
        }
        A *= f; B *= f;
        float l_ = L + 0.3963377774f * A + 0.2158037573f * B;
        float m_ = L - 0.1055613458f * A - 0.0638541728f * B;
        float s_ = L - 0.0894841775f * A - 1.2914855480f * B;
        float l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_;
        float3 o = float3(4.0767416621f * l3 - 3.3077115913f * m3 + 0.2309699292f * s3,
                          -1.2684380046f * l3 + 2.6097574011f * m3 - 0.3413193965f * s3,
                          -0.0041960863f * l3 - 0.7034186147f * m3 + 1.7076147010f * s3);
        return float4(max(float3(0.0f), o), s.a);
    }

    // clarity: base = blurred perceptual luma. k = (amount, midtonePower, 0, 0)
    [[ stitchable ]] float4 lookClarity(coreimage::sample_t s, coreimage::sample_t base, float4 k, float2 gam, float4 lum) {
        float y = dot(s.rgb, lum.rgb);
        float q = lk_perc(y, gam.x);
        float mid = 1.0f - pow(fabs(2.0f * clamp(q, 0.0f, 1.0f) - 1.0f), k.y);
        float q2 = max(0.0f, q + k.x * (q - base.r) * mid);
        float ratio = y > 1e-9f ? lk_lin(q2, gam.y) / y : 1.0f;
        return float4(s.rgb * ratio, s.a);
    }

    // sharpen: blur = blurred perceptual luma. k = (amount, threshold, 0, 0)
    [[ stitchable ]] float4 lookSharpen(coreimage::sample_t s, coreimage::sample_t blur, float4 k, float2 gam, float4 lum) {
        float y = dot(s.rgb, lum.rgb);
        float q = lk_perc(y, gam.x);
        float hp = q - blur.r;
        float mask = lk_smooth(k.y, 2.0f * k.y, fabs(hp));
        float q2 = max(0.0f, q + k.x * hp * mask);
        float ratio = y > 1e-9f ? lk_lin(q2, gam.y) / y : 1.0f;
        return float4(s.rgb * ratio, s.a);
    }

    // vignette: k = (amountStops, edge0, edge1, invHalfDiagonal), c = centre in pixels
    [[ stitchable ]] float4 lookVignette(coreimage::sample_t s, float4 k, float2 c, coreimage::destination dest) {
        float r = length(dest.coord() - c) * k.w;
        float g = exp2(k.x * lk_smooth(k.y, k.z, r));
        return float4(s.rgb * g, s.a);
    }

    // Argument echo (tests only): what each parameter slot receives, in the layouts the stages use.
    [[ stitchable ]] float4 lookEcho442(coreimage::sample_t s, float4 a, float4 b, float2 c) {
        return float4(s.r + 1000.0f * a.x + 1000000.0f * b.x, a.y + 1000.0f * b.y + 1000000.0f * c.x, a.z + 1000.0f * b.z + 1000000.0f * c.y, a.w + 1000.0f * b.w);
    }
    [[ stitchable ]] float4 lookEcho44(coreimage::sample_t s, float4 a, float4 b) {
        return float4(s.r + 1000.0f * a.x + 1000000.0f * b.x, a.y + 1000.0f * b.y, a.z + 1000.0f * b.z, a.w + 1000.0f * b.w);
    }
    [[ stitchable ]] float4 lookEcho424(coreimage::sample_t s, float4 a, float2 b, float4 c) {
        return float4(s.r + 1000.0f * a.x + 1000000.0f * c.x, a.y + 1000.0f * b.x + 1000000.0f * c.y, a.z + 1000.0f * b.y + 1000000.0f * c.z, a.w + 1000.0f * c.w);
    }
    """

    struct CompileError: Error, CustomStringConvertible { let description: String }

    /// The stage kernels, compiled when the pipeline is made.
    static let stageNames = ["lookLuma", "lookBase", "lookExposure", "lookWhiteBalance", "lookPre", "lookTone", "lookContrast", "lookColour", "lookClarity", "lookSharpen", "lookVignette"]

    private let header: String
    private let blocks: [String: String]             // function name → its source block
    private let lock = NSLock()
    private var compiled: [String: CIKernel] = [:]
    var byName: [String: CIKernel] { lock.withLock { compiled } }

    /// One compile per kernel: the helpers plus a single `[[ stitchable ]]` function. Compiling
    /// the whole source at once (macOS 15.x) hands back kernels whose names and code are mixed up
    /// between functions with the same parameter list (`LookPipelineTests.
    /// testKernelArgumentsArriveInOrder` caught `lookPre` running the echo kernel's code), so each
    /// `kernels(withMetalString:)` call here can only ever return the one function it was given.
    /// The stage kernels compile here; the echo kernels (tests) compile on first use.
    init() throws {
        let marker = "[[ stitchable ]]"
        guard let first = Self.source.range(of: marker) else { throw CompileError(description: "no kernels in the source") }
        header = String(Self.source[..<first.lowerBound])
        var rest = String(Self.source[first.lowerBound...])
        var list: [String] = []
        while let next = rest.range(of: marker, options: [], range: rest.index(after: rest.startIndex)..<rest.endIndex) {
            list.append(String(rest[..<next.lowerBound]))
            rest = String(rest[next.lowerBound...])
        }
        list.append(rest)
        var named: [String: String] = [:]
        for block in list {
            guard let open = block.range(of: "("), let space = block[..<open.lowerBound].lastIndex(of: " ") else { throw CompileError(description: "unreadable kernel block") }
            named[String(block[block.index(after: space)..<open.lowerBound])] = block
        }
        blocks = named
        for name in Self.stageNames { _ = try kernel(name) }
    }

    /// `LUMINA_KERNEL_SALT` (the probe's cold run, never set in the app): every kernel function is
    /// compiled under a salted name, so neither Core Image's nor Metal's on-disk cache has seen its
    /// programs, as on the first launch after an update that changed a kernel. The maths is unchanged.
    static let salt: String? = {
        let s = (ProcessInfo.processInfo.environment["LUMINA_KERNEL_SALT"] ?? "").filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return s.isEmpty ? nil : s
    }()

    /// The compiled kernel, compiling its block on first use.
    func kernel(_ name: String) throws -> CIKernel {
        if let k = lock.withLock({ compiled[name] }) { return k }
        guard var block = blocks[name] else { throw CompileError(description: "no kernel named \(name); have \(blocks.keys.sorted())") }
        var function = name
        if let salt = Self.salt {
            function = "\(name)_\(salt)"
            block = block.replacingOccurrences(of: " \(name)(", with: " \(function)(")
        }
        let list = try CIKernel.kernels(withMetalString: header + block)
        guard list.count == 1, let k = list.first, k.name == function else { throw CompileError(description: "\(name): expected one kernel, got \(list.map(\.name))") }
        lock.withLock { compiled[name] = k }
        return k
    }

    /// One shared set per process.
    nonisolated(unsafe) private static var _shared: LookKernels?
    private static let sharedLock = NSLock()
    static func shared() throws -> LookKernels {
        sharedLock.lock(); defer { sharedLock.unlock() }
        if let k = _shared { return k }
        let k = try LookKernels()
        _shared = k
        return k
    }

    /// Runs a colour kernel over `extent`. Inputs map 1:1, so the region of interest is the output rect.
    func apply(_ name: String, extent: CGRect, _ args: [Any]) -> CIImage? {
        (try? kernel(name))?.apply(extent: extent, roiCallback: { _, r in r }, arguments: args)
    }
}
