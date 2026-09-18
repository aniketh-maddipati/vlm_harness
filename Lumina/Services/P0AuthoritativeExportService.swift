import Foundation

/// P0 kept-set export through the same authoritative RAW graph used by
/// settled inspection. Serialized by `DevelopRenderScheduler` to stay off the
/// visible rendering lane.
nonisolated enum P0AuthoritativeExportService {
    enum ExportError: LocalizedError {
        case noKeptPhotographs
        case originalUnavailable(String)
        case renderFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noKeptPhotographs:
                return "Keep a photograph before exporting."
            case .originalUnavailable(let name):
                return "\(name) is offline."
            case .renderFailed(let name):
                return "\(name) could not be rendered."
            case .writeFailed(let name):
                return "\(name) could not be written."
            }
        }
    }

    struct Outcome: Sendable {
        let root: URL
        let urls: [URL]
        let assetIDs: [UUID]
    }

    static func export(
        shootName: String,
        assets: [AssetRecord],
        to destination: URL
    ) async throws -> Outcome {
        let kept = assets.filter { $0.cull == .keep }
        guard !kept.isEmpty else { throw ExportError.noKeptPhotographs }
        let root = destination.appendingPathComponent(shootName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var urls: [URL] = []
        var ids: [UUID] = []
        for (index, asset) in kept.enumerated() {
            let rawURL = URL(fileURLWithPath: asset.source.originalPath)
            guard asset.source.availability != .missing,
                  FileManager.default.fileExists(atPath: rawURL.path) else {
                throw ExportError.originalUnavailable(asset.filename)
            }
            guard let bitmap = await DevelopRenderGraph.renderExportBitmap(
                rawURL: rawURL,
                photoID: asset.id,
                recipe: asset.recipe ?? .neutral
            ) else {
                throw ExportError.renderFailed(asset.filename)
            }
            let stem = rawURL.deletingPathExtension().lastPathComponent
            let name = String(format: "%04d_%@.tif", index + 1, stem)
            let output = root.appendingPathComponent(name)
            guard DevelopRenderGraph.exportTIFF(
                cgImage: bitmap,
                to: output,
                preserveMetadataFrom: rawURL
            ) else {
                throw ExportError.writeFailed(asset.filename)
            }
            urls.append(output)
            ids.append(asset.id)
        }
        return Outcome(root: root, urls: urls, assetIDs: ids)
    }
}
