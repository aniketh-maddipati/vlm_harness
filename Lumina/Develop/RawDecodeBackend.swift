import CoreImage
import Foundation

/// Internal seam for measured decoder experiments. Production intentionally
/// registers only Apple's camera/color pipeline.
nonisolated protocol RawDecodeBackend: Sendable {
    var identifier: String { get }
    func makeFilter(imageURL: URL) -> CIRAWFilter?
}

nonisolated struct AppleRawDecodeBackend: RawDecodeBackend {
    let identifier = "apple-ciraw"

    func makeFilter(imageURL: URL) -> CIRAWFilter? {
        CIRAWFilter(imageURL: imageURL)
    }
}

nonisolated enum RawDecodeBackendRegistry {
    static let production: any RawDecodeBackend = AppleRawDecodeBackend()

    #if !LUMINA_SHIPPING_APP
    /// Non-shipping benchmark inventory. Alternate libraries remain absent
    /// until license, format, fidelity, and speed evidence is reviewed.
    static let benchmarkInventory = [
        RawBackendBenchmarkDescriptor(
            identifier: "apple-ciraw",
            linked: true,
            role: "production"
        ),
        RawBackendBenchmarkDescriptor(
            identifier: "libraw",
            linked: false,
            role: "compatibility candidate"
        ),
        RawBackendBenchmarkDescriptor(
            identifier: "rawspeed",
            linked: false,
            role: "supported-format decode candidate"
        ),
    ]
    #endif
}

#if !LUMINA_SHIPPING_APP
nonisolated struct RawBackendBenchmarkDescriptor: Codable, Hashable, Sendable {
    let identifier: String
    let linked: Bool
    let role: String
}
#endif
