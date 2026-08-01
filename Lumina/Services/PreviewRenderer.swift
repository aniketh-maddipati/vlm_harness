import CoreImage
import AppKit

enum PreviewRenderer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func render(url: URL, adjustments: DevelopAdjustments) -> NSImage? {
        guard let image = CIImage(contentsOf: url) else { return nil }
        let output = apply(adjustments, to: image)
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }

    static func apply(_ adjustments: DevelopAdjustments, to image: CIImage) -> CIImage {
        var result = image

        if adjustments.exposure != 0,
           let filter = CIFilter(name: "CIExposureAdjust") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(adjustments.exposure, forKey: kCIInputEVKey)
            result = filter.outputImage ?? result
        }

        if adjustments.contrast != 0,
           let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(1 + adjustments.contrast / 100.0, forKey: kCIInputContrastKey)
            result = filter.outputImage ?? result
        }

        if adjustments.vibrance != 0,
           let filter = CIFilter(name: "CIVibrance") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(adjustments.vibrance / 100.0, forKey: "inputAmount")
            result = filter.outputImage ?? result
        }

        if adjustments.highlights != 0 || adjustments.shadows != 0,
           let filter = CIFilter(name: "CIHighlightShadowAdjust") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(1 - adjustments.highlights / 200.0, forKey: "inputHighlightAmount")
            filter.setValue(1 + adjustments.shadows / 200.0, forKey: "inputShadowAmount")
            result = filter.outputImage ?? result
        }

        if adjustments.temperature != 0,
           let filter = CIFilter(name: "CITemperatureAndTint") {
            filter.setValue(result, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            filter.setValue(CIVector(x: 6500 + adjustments.temperature, y: 0), forKey: "inputTargetNeutral")
            result = filter.outputImage ?? result
        }

        return result
    }
}
