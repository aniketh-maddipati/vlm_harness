import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Turns a decoded RAW stage into `ImageStats`.
///
/// Lives outside `PreparedRawSession` so the render data plane never reads an
/// actor's statics (see AGENTS.md on isolation). The `CIContext` is created once
/// and is safe to share — measuring is read-only.
nonisolated enum ImageStatsRenderer {
    /// Small enough that measuring never competes with a scrub frame, large
    /// enough that clip fractions still mean something.
    static let sampleLongEdge = 256

    private static let context = CIContext(options: DevelopColorPolicy.ciContextOptions)

    /// Measures an as-shot stage image. `nativeTemperature` comes from the decoder.
    static func stats(from image: CIImage, nativeTemperature: Double?) -> ImageStats? {
        let bounds = image.extent.integral
        guard !bounds.isEmpty, bounds.width.isFinite, bounds.height.isFinite else { return nil }
        guard let cgImage = context.createCGImage(
            image,
            from: bounds,
            format: .RGBAh,
            colorSpace: DevelopColorPolicy.displayColorSpace
        ) else { return nil }
        guard let measured = ImageStats.measure(
            cgImage: cgImage,
            maxSampleEdge: sampleLongEdge
        ) else { return nil }
        return measured.withCameraContext(
            nativeTemperature: nativeTemperature,
            horizonAngle: horizonAngle(in: cgImage)
        )
    }

    /// Horizon tilt in degrees, or nil when Vision does not find one.
    ///
    /// Optional by design: a frame with no usable horizon simply gets no
    /// straighten suggestion rather than an invented one.
    static func horizonAngle(in cgImage: CGImage) -> Double? {
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first as? VNHorizonObservation else { return nil }
        return Double(observation.angle) * 180 / .pi
    }
}
