import AppKit
import CoreImage
import Foundation

enum ExportService {
    struct ExportManifest: Codable {
        var project: String
        var exportedAt: Date
        var files: [ExportEntry]
    }

    struct ExportEntry: Codable {
        var order: Int
        var source: String
        var export: String
        var tier: String
        var cullScore: Double
    }

    static func exportCarousel(
        photos: [PhotoRecord],
        projectName: String,
        profile: DevelopProfile,
        globalAdjustments: DevelopAdjustments,
        to folder: URL
    ) throws -> URL {
        let exportDir = folder.appendingPathComponent("grid_4x5", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let keeps = photos
            .filter { $0.tier == .keep && $0.isBurstHero }
            .sorted { $0.cullScore > $1.cullScore }
            .prefix(12)

        var entries: [ExportEntry] = []

        for (index, photo) in keeps.enumerated() {
            guard let thumbPath = photo.thumbPath else { continue }
            let thumbURL = URL(fileURLWithPath: thumbPath)
            let perPhoto = photo.perPhotoAdjustments ?? .zero
            let merged = profile.asAdjustments.merged(with: globalAdjustments).merged(with: perPhoto)

            guard var ciImage = CIImage(contentsOf: thumbURL) else { continue }
            ciImage = PreviewRenderer.apply(merged, to: ciImage)

            let cropRect = cropRect45(for: ciImage)
            ciImage = ciImage.cropped(to: cropRect)

            let scale = 1800.0 / max(cropRect.width, cropRect.height)
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            let context = CIContext()
            guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { continue }

            let filename = String(format: "%02d_%@", index + 1, photo.filename.replacingOccurrences(of: ".ARW", with: ".jpg"))
            let dest = exportDir.appendingPathComponent(filename)
            try writeJPEG(cgImage: cg, to: dest, quality: 0.9)

            entries.append(ExportEntry(
                order: index + 1,
                source: photo.filename,
                export: filename,
                tier: photo.tier.rawValue,
                cullScore: photo.cullScore
            ))
        }

        let manifest = ExportManifest(project: projectName, exportedAt: Date(), files: entries)
        let manifestURL = folder.appendingPathComponent("export.json")
        let data = try JSONEncoder.pretty.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)

        return exportDir
    }

    private static func cropRect45(for image: CIImage) -> CGRect {
        let extent = image.extent
        let targetAspect = 4.0 / 5.0
        let imageAspect = extent.width / extent.height

        if imageAspect > targetAspect {
            let width = extent.height * targetAspect
            let x = extent.origin.x + (extent.width - width) / 2
            return CGRect(x: x, y: extent.origin.y, width: width, height: extent.height)
        } else {
            let height = extent.width / targetAspect
            let y = extent.origin.y + (extent.height - height) / 2
            return CGRect(x: extent.origin.x, y: y, width: extent.width, height: height)
        }
    }

    private static func writeJPEG(cgImage: CGImage, to url: URL, quality: CGFloat) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            throw ExportError.writeFailed
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(dest, cgImage, options)
        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.writeFailed
        }
    }
}

enum ExportError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .writeFailed: "Failed to write JPEG export"
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
