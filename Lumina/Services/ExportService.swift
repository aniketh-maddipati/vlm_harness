import AppKit
import CoreImage
import Foundation

enum ExportService {
    struct ExportManifest: Codable {
        var project: String
        var exportedAt: Date
        var collections: [CollectionManifest]
    }

    struct CollectionManifest: Codable {
        var name: String
        var aspect: String
        var files: [ExportEntry]
    }

    struct ExportEntry: Codable {
        var order: Int
        var source: String
        var export: String
        var tier: String
        var cullScore: Double
        var recipeNeighbors: [String]
    }

    static func draftCollections(from photos: [PhotoRecord]) -> [ExportCollection] {
        let keeps = photos
            .filter { $0.tier == .keep && ($0.isBurstHero || $0.isClusterHero) }
            .sorted { $0.cullScore > $1.cullScore }
        let ids = Array(keeps.prefix(12).map(\.id))
        let heroes = Array(keeps.prefix(6).map(\.id))
        return [
            ExportCollection(name: "heroes", aspect: .fourByFive, photoIDs: heroes),
            ExportCollection(name: "grid_carousel", aspect: .fourByFive, photoIDs: ids),
            ExportCollection(name: "reel_sequence", aspect: .nineBySixteen, photoIDs: Array(keeps.prefix(8).map(\.id))),
        ]
    }

    static func exportCollections(
        project: LuminaProject,
        globalAdjustments: DevelopAdjustments,
        aspects: [ExportAspect] = [.fourByFive],
        writeXMP: Bool = true,
        to folder: URL,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> URL {
        let exportRoot = folder.appendingPathComponent(project.name, isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

        var collections = project.collections
        if collections.isEmpty {
            collections = draftCollections(from: project.photos)
        }

        // Filter to requested aspects
        let toExport = collections.filter { aspects.contains($0.aspect) || aspects.isEmpty }
        var manifestCollections: [CollectionManifest] = []

        let photoByID = Dictionary(uniqueKeysWithValues: project.photos.map { ($0.id, $0) })

        for collection in toExport {
            progress?("Exporting \(collection.name)…")
            let dir = exportRoot.appendingPathComponent("\(collection.name)_\(collection.aspect.rawValue.replacingOccurrences(of: ":", with: "x"))", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let photos = collection.photoIDs.compactMap { photoByID[$0] }
            let entries = try await exportPhotosParallel(
                photos: photos,
                project: project,
                globalAdjustments: globalAdjustments,
                aspect: collection.aspect,
                to: dir,
                writeXMP: writeXMP
            )
            manifestCollections.append(CollectionManifest(
                name: collection.name,
                aspect: collection.aspect.rawValue,
                files: entries
            ))
        }

        let manifest = ExportManifest(
            project: project.name,
            exportedAt: Date(),
            collections: manifestCollections
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: exportRoot.appendingPathComponent("export.json"), options: .atomic)
        return exportRoot
    }

    /// Back-compat single carousel export.
    static func exportCarousel(
        photos: [PhotoRecord],
        projectName: String,
        profile: DevelopRecipe,
        globalAdjustments: DevelopAdjustments,
        to folder: URL
    ) throws -> URL {
        var project = LuminaProject(name: projectName, profile: profile, photos: photos)
        project.collections = draftCollections(from: photos)
        let sem = DispatchSemaphore(value: 0)
        var result: Result<URL, Error>!
        Task {
            do {
                let url = try await exportCollections(
                    project: project,
                    globalAdjustments: globalAdjustments,
                    aspects: [.fourByFive],
                    to: folder
                )
                result = .success(url)
            } catch {
                result = .failure(error)
            }
            sem.signal()
        }
        sem.wait()
        return try result.get()
    }

    private static func exportPhotosParallel(
        photos: [PhotoRecord],
        project: LuminaProject,
        globalAdjustments: DevelopAdjustments,
        aspect: ExportAspect,
        to dir: URL,
        writeXMP: Bool
    ) async throws -> [ExportEntry] {
        let indexed = Array(photos.enumerated())
        return try await withThrowingTaskGroup(of: ExportEntry?.self) { group in
            for (index, photo) in indexed {
                group.addTask {
                    try exportOne(
                        photo: photo,
                        order: index + 1,
                        project: project,
                        globalAdjustments: globalAdjustments,
                        aspect: aspect,
                        to: dir,
                        writeXMP: writeXMP
                    )
                }
            }
            var entries: [ExportEntry] = []
            for try await entry in group {
                if let entry { entries.append(entry) }
            }
            return entries.sorted { $0.order < $1.order }
        }
    }

    private static func exportOne(
        photo: PhotoRecord,
        order: Int,
        project: LuminaProject,
        globalAdjustments: DevelopAdjustments,
        aspect: ExportAspect,
        to dir: URL,
        writeXMP: Bool
    ) throws -> ExportEntry? {
        let offsets = globalAdjustments.merged(with: photo.perPhotoAdjustments ?? .zero)
        let recipe = photo.effectiveRecipe

        // Prefer full RAW demosaic path
        var cgImage = DevelopEngine.renderFullRAW(
            rawURL: URL(fileURLWithPath: photo.rawPath),
            recipe: recipe,
            offsets: offsets
        )

        if cgImage == nil {
            // Fallback: proxy / thumb
            let src = photo.proxyPath ?? photo.thumbPath
            guard let src,
                  let url = Optional(URL(fileURLWithPath: src)),
                  let ci = CIImage(contentsOf: url) else { return nil }
            let graded = DevelopEngine.apply(recipe: recipe.applying(offsets), to: ci)
            let ctx = CIContext()
            cgImage = ctx.createCGImage(graded, from: graded.extent)
        }

        guard var cg = cgImage else { return nil }
        if let cropped = crop(cgImage: cg, aspect: aspect) {
            cg = cropped
        }
        if let scaled = scale(cgImage: cg, longEdge: 1800) {
            cg = scaled
        }

        let stem = URL(fileURLWithPath: photo.filename).deletingPathExtension().lastPathComponent
        let filename = String(format: "%02d_%@.jpg", order, stem)
        let dest = dir.appendingPathComponent(filename)
        guard PreviewExtractor.writeJPEG(cgImage: cg, to: dest, quality: 0.92) else {
            throw ExportError.writeFailed
        }

        if writeXMP {
            try? XMPDevelopParser.writeSidecar(
                recipe: recipe.applying(offsets),
                nextTo: URL(fileURLWithPath: photo.rawPath)
            )
        }

        return ExportEntry(
            order: order,
            source: photo.filename,
            export: filename,
            tier: photo.tier.rawValue,
            cullScore: photo.cullScore,
            recipeNeighbors: recipe.sourceNeighbors
        )
    }

    private static func crop(cgImage: CGImage, aspect: ExportAspect) -> CGImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let target = aspect.ratio
        let current = w / h
        var rect: CGRect
        if current > target {
            let nw = h * target
            rect = CGRect(x: (w - nw) / 2, y: 0, width: nw, height: h)
        } else {
            let nh = w / target
            rect = CGRect(x: 0, y: (h - nh) / 2, width: w, height: nh)
        }
        return cgImage.cropping(to: rect)
    }

    private static func scale(cgImage: CGImage, longEdge: CGFloat) -> CGImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let scale = longEdge / max(w, h)
        if scale >= 0.99 { return cgImage }
        let nw = Int(w * scale)
        let nh = Int(h * scale)
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: nw, height: nh,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }
}

enum ExportError: LocalizedError {
    case writeFailed
    var errorDescription: String? { "Failed to write JPEG export" }
}
