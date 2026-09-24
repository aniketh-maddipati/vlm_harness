import Foundation

nonisolated struct P0ExportSettings: Codable, Equatable, Sendable {
    enum Format: String, Codable, CaseIterable, Sendable { case jpeg, tiff }
    var format: Format = .jpeg
    /// Zero means full size; resizing never enlarges a photograph.
    var longEdge: Int = 0
    var quality: Double = 0.95

    var isValid: Bool { (longEdge == 0 || (256...20000).contains(longEdge)) && quality.isFinite && (0.1...1).contains(quality) }
}

nonisolated struct P0ExportPlan: Codable, Sendable {
    struct Item: Codable, Sendable {
        let assetID: UUID
        let sourcePath: String
        let recipe: EditRecipe
        let filename: String
    }
    let id: UUID
    let shootID: UUID
    let settings: P0ExportSettings
    let items: [Item]

    @MainActor
    static func make(shootID: UUID, assets: [AssetRecord], order: [UUID], settings: P0ExportSettings) throws -> Self {
        guard settings.isValid else { throw P0ExportJobStore.Failure.invalidPlan }
        let kept = assets.enumerated().filter { $0.element.cull == .keep }
        let byID = Dictionary(kept.map { ($0.element.id, $0.element) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var ids = order.filter { byID[$0] != nil && seen.insert($0).inserted }
        let remainder = kept.sorted { a, b in
            switch (a.element.capturedAt, b.element.capturedAt) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset != b.offset ? a.offset < b.offset : a.element.id.uuidString < b.element.id.uuidString
            }
        }
        ids += remainder.compactMap { seen.insert($0.element.id).inserted ? $0.element.id : nil }
        guard !ids.isEmpty else { throw P0ExportJobStore.Failure.emptySet }
        let width = max(4, String(ids.count).count)
        return Self(id: UUID(), shootID: shootID, settings: settings, items: ids.enumerated().map { index, id in
            let asset = byID[id]!
            let stem = URL(fileURLWithPath: asset.filename).deletingPathExtension().lastPathComponent
            let safe = String(stem.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? Character($0) : "_" }.prefix(80))
            return Item(assetID: id, sourcePath: asset.source.originalPath, recipe: asset.recipe ?? .neutral,
                        filename: String(format: "%0*d_", width, index + 1) + safe + (settings.format == .jpeg ? ".jpg" : ".tif"))
        })
    }
}
