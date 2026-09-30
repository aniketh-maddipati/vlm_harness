import CoreImage
import Foundation

/// The stage kernels, as Metal source compiled at first use with `CIKernel.kernels(withMetalString:)`
/// (macOS 14+). Source strings, not a `.ci.metal` file, so the app target, the `lumina-render`
/// SwiftPM tool and the probe all build the same kernels with no compiler flags. Each function
/// repeats a `LookMath` formula; `LookPipelineTests` checks the two agree on flat patches.
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
    static float lk_cbrt(float x) { return x < 0.0f ? -pow(-x, 1.0f / 3.0f) : pow(x, 1.0f / 3.0f); }
    static float lk_curve(float p, float m, float a) {
        if (p <= 0.0f) return 0.0f;
        if (p >= 1.0f) return p;
        return p < m ? m * pow(p / m, a) : 1.0f - (1.0f - m) * pow((1.0f - p) / (1.0f - m), a);
    }

    extern "C" {
    namespace coreimage {

    // luma (linear), or perceptual luma when invGamma > 0: the images the blurs work on
    float4 lookLuma(sample_t s, float4 lum, float invGamma) {
        float y = dot(s.rgb, lum.rgb);
        if (invGamma > 0.0f) y = lk_perc(y, invGamma);
        return float4(y, y, y, 1.0f);
    }

    // exposure + whiteBalance + whitesBlacks. wb = per-channel gains (already × exposure gain);
    // wbk = (whitesAmt, blacksAmt, whitesPower, blacksPower); gam = (invGamma, gamma)
    float4 lookPre(sample_t s, float4 wb, float4 wbk, float2 gam) {
        float3 c = s.rgb * wb.rgb;
        if (wbk.x != 0.0f || wbk.y != 0.0f) {
            float3 p = pow(max(float3(0.0f), c), float3(gam.x));
            float3 pc = clamp(p, 0.0f, 1.0f);
            float3 q = p - wbk.y * pow(1.0f - pc, float3(wbk.w)) + wbk.x * pow(pc, float3(wbk.z));
            c = pow(max(float3(0.0f), q), float3(gam.y));
        }
        return float4(c, s.a);
    }

    // tone: base = blurred linear luma. sh = (shadowsAmt, lo, hi, 0), hl = (highlightsAmt, lo, hi, detailGain)
    float4 lookTone(sample_t s, sample_t base, float4 sh, float4 hl, float2 gam, float4 lum) {
        float bp = lk_perc(base.r, gam.x);
        float g = exp2(sh.x * (1.0f - lk_smooth(sh.y, sh.z, bp)) + hl.x * lk_smooth(hl.y, hl.z, bp));
        if (fabs(hl.w - 1.0f) > 1e-9f) {
            float y = dot(s.rgb, lum.rgb);
            g *= pow(max(1e-6f, y) / max(1e-6f, base.r), hl.w - 1.0f);
        }
        return float4(s.rgb * g, s.a);
    }

    // contrast: k = (midpoint, slope a, lumaMix, 0)
    float4 lookContrast(sample_t s, float4 k, float2 gam, float4 lum) {
        float3 per = float3(lk_lin(lk_curve(lk_perc(s.r, gam.x), k.x, k.y), gam.y),
                            lk_lin(lk_curve(lk_perc(s.g, gam.x), k.x, k.y), gam.y),
                            lk_lin(lk_curve(lk_perc(s.b, gam.x), k.x, k.y), gam.y));
        float y = dot(s.rgb, lum.rgb);
        float ratio = y > 1e-9f ? lk_lin(lk_curve(lk_perc(y, gam.x), k.x, k.y), gam.y) / y : 1.0f;
        float3 byLuma = s.rgb * ratio;
        return float4(mix(per, byLuma, k.z), s.a);
    }

    // colour: k1 = (satFactor, vibranceAmt, chromaMax, protectOn), k2 = (skinHue, skinWidth, skinProtect, bw)
    float4 lookColour(sample_t s, float4 k1, float4 k2) {
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
            float protect = k1.w > 0.5f ? 1.0f - k2.z * skin : 1.0f;
            float vib = max(0.0f, 1.0f + k1.y * (1.0f - min(1.0f, C / k1.z)) * protect);
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
    float4 lookClarity(sample_t s, sample_t base, float4 k, float2 gam, float4 lum) {
        float y = dot(s.rgb, lum.rgb);
        float q = lk_perc(y, gam.x);
        float mid = 1.0f - pow(fabs(2.0f * clamp(q, 0.0f, 1.0f) - 1.0f), k.y);
        float q2 = max(0.0f, q + k.x * (q - base.r) * mid);
        float ratio = y > 1e-9f ? lk_lin(q2, gam.y) / y : 1.0f;
        return float4(s.rgb * ratio, s.a);
    }

    // sharpen: blur = blurred perceptual luma. k = (amount, threshold, 0, 0)
    float4 lookSharpen(sample_t s, sample_t blur, float4 k, float2 gam, float4 lum) {
        float y = dot(s.rgb, lum.rgb);
        float q = lk_perc(y, gam.x);
        float hp = q - blur.r;
        float mask = lk_smooth(k.y, 2.0f * k.y, fabs(hp));
        float q2 = max(0.0f, q + k.x * hp * mask);
        float ratio = y > 1e-9f ? lk_lin(q2, gam.y) / y : 1.0f;
        return float4(s.rgb * ratio, s.a);
    }

    // vignette: k = (amountStops, edge0, edge1, invHalfDiagonal), c = centre in pixels
    float4 lookVignette(sample_t s, float4 k, float2 c, destination dest) {
        float r = length(dest.coord() - c) * k.w;
        float g = exp2(k.x * lk_smooth(k.y, k.z, r));
        return float4(s.rgb * g, s.a);
    }

    }
    }
    """

    struct CompileError: Error, CustomStringConvertible { let description: String }

    let byName: [String: CIKernel]

    init() throws {
        let list = try CIKernel.kernels(withMetalString: Self.source)
        var d: [String: CIKernel] = [:]
        for k in list { d[k.name] = k }
        for name in ["lookLuma", "lookPre", "lookTone", "lookContrast", "lookColour", "lookClarity", "lookSharpen", "lookVignette"] where d[name] == nil {
            throw CompileError(description: "kernel \(name) missing after compile; got \(d.keys.sorted())")
        }
        byName = d
    }

    /// One shared compile per process.
    nonisolated(unsafe) private static var _shared: LookKernels?
    private static let lock = NSLock()
    static func shared() throws -> LookKernels {
        lock.lock(); defer { lock.unlock() }
        if let k = _shared { return k }
        let k = try LookKernels()
        _shared = k
        return k
    }

    /// Runs a colour kernel over `extent`. Inputs map 1:1, so the region of interest is the output rect.
    func apply(_ name: String, extent: CGRect, _ args: [Any]) -> CIImage? {
        byName[name]?.apply(extent: extent, roiCallback: { _, r in r }, arguments: args)
    }
}
