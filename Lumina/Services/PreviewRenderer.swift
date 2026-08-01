import CoreImage
import AppKit

enum PreviewRenderer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func render(url: URL, profile: DevelopProfile, offsets: DevelopAdjustments = .zero) -> NSImage? {
        guard let image = CIImage(contentsOf: url) else { return nil }
        let bounds = image.extent
        let output = apply(profile: profile, offsets: offsets, to: image).cropped(to: bounds)
        guard let cg = context.createCGImage(output, from: bounds) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: bounds.width, height: bounds.height))
    }

    static func apply(profile: DevelopProfile, offsets: DevelopAdjustments, to image: CIImage) -> CIImage {
        let bounds = image.extent
        var result = image

        let exposure = profile.exposure + offsets.exposure
        let contrast = profile.contrast + offsets.contrast
        let highlights = profile.highlights + offsets.highlights
        let shadows = profile.shadows + offsets.shadows
        let vibrance = profile.vibrance + offsets.vibrance
        // Profile temperature is absolute Kelvin; offsets are ± shift from profile.
        let temperature = profile.temperature + offsets.temperature

        if exposure != 0,
           let filter = CIFilter(name: "CIExposureAdjust") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(exposure, forKey: kCIInputEVKey)
            result = filter.outputImage ?? result
        }

        if contrast != 0,
           let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(1 + contrast / 100.0, forKey: kCIInputContrastKey)
            result = filter.outputImage ?? result
        }

        if vibrance != 0,
           let filter = CIFilter(name: "CIVibrance") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(vibrance / 100.0, forKey: "inputAmount")
            result = filter.outputImage ?? result
        }

        if highlights != 0 || shadows != 0,
           let filter = CIFilter(name: "CIHighlightShadowAdjust") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(1 - highlights / 100.0, forKey: "inputHighlightAmount")
            filter.setValue(1 + shadows / 100.0, forKey: "inputShadowAmount")
            result = filter.outputImage ?? result
        }

        if temperature != 6500,
           let filter = CIFilter(name: "CITemperatureAndTint") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            filter.setValue(CIVector(x: temperature, y: 0), forKey: "inputTargetNeutral")
            result = filter.outputImage ?? result
        }

        return result.cropped(to: bounds)
    }
}
