import Foundation
import ImageIO

struct ElasticCaptureFacts: Equatable, Sendable {
    var camera: String
    var exposure: String

    static let unknown = ElasticCaptureFacts(camera: "", exposure: "")

    static func read(atPath path: String) async -> ElasticCaptureFacts {
        guard !path.isEmpty else { return .unknown }
        return await Task.detached(priority: .utility) {
            readSynchronously(atPath: path)
        }.value
    }

    /// `a7 iii · 35 mm` and `1/250 · f/2.8 · iso 400`, leaving out whatever the
    /// file does not say rather than inventing a placeholder for it.
    nonisolated static func readSynchronously(atPath path: String) -> ElasticCaptureFacts {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return .unknown }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        var camera: [String] = []
        if let model = (tiff[kCGImagePropertyTIFFModel] as? String)?
            .trimmingCharacters(in: .whitespaces), !model.isEmpty {
            camera.append(model.lowercased())
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double, focal > 0 {
            camera.append("\(Int(focal.rounded())) mm")
        }

        var exposure: [String] = []
        if let seconds = exif[kCGImagePropertyExifExposureTime] as? Double, seconds > 0 {
            exposure.append(shutterLabel(seconds))
        }
        if let aperture = exif[kCGImagePropertyExifFNumber] as? Double, aperture > 0 {
            exposure.append("f/" + trimmed(aperture))
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first, iso > 0 {
            exposure.append("iso \(iso)")
        }

        return ElasticCaptureFacts(
            camera: camera.joined(separator: " · "),
            exposure: exposure.joined(separator: " · ")
        )
    }

    /// `1/250` under a second, `2s` over it — how the camera itself says it.
    nonisolated private static func shutterLabel(_ seconds: Double) -> String {
        if seconds >= 1 { return trimmed(seconds) + "s" }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    /// `2.8` keeps its decimal, `4.0` loses it — apertures read as the lens says them.
    nonisolated private static func trimmed(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

/// The table, compressed. Shoot order, the cursor tile bigger than the rest, and a
/// wider gap wherever one moment ends and the next begins.
