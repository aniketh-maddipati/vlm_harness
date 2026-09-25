import Foundation

nonisolated struct P0AutoSource: Equatable, Sendable {
    let key: String
    let reference: SourceReference
    let fileSize: Int64?

    init(_ asset: AssetRecord) {
        key = asset.sourceKey
        reference = asset.source
        fileSize = asset.fileSize
    }
}

nonisolated struct P0AutoRun: Sendable {
    let id: UUID
    let shootID: UUID?
    let contextID: UUID
    let targetIDs: [UUID]
    let scope: String
    let sources: [UUID: P0AutoSource]
    let recipeFingerprints: [UUID: String]
}

nonisolated struct P0AutoReceipt: Equatable, Sendable {
    let adjusted: Int
    let unchanged: Int
    let unmeasured: Int
    let protected: Int
    let skipped: Int

    var label: String {
        var parts = ["\(adjusted) adjusted"]
        if unchanged > 0 { parts.append("\(unchanged) unchanged") }
        if unmeasured > 0 { parts.append("\(unmeasured) unmeasured") }
        if protected > 0 { parts.append("\(protected) protected") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.joined(separator: " · ")
    }
}
