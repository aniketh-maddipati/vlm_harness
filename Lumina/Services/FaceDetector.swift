import Vision
import AppKit
import ImageIO

enum FaceDetector {
    static func hasFace(in imageURL: URL) -> Bool {
        if let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
                return hasFace(in: cg)
            }
        }
        guard let image = NSImage(contentsOf: imageURL),
              let cg = rasterisedCGImage(from: image) else {
            return false
        }
        return hasFace(in: cg)
    }

    static func hasFace(in cgImage: CGImage) -> Bool {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return !(request.results?.isEmpty ?? true)
        } catch {
            return false
        }
    }

    static func faceBounds(in cgImage: CGImage) -> CGRect? {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first?.boundingBox
        } catch {
            return nil
        }
    }

    private static func rasterisedCGImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
