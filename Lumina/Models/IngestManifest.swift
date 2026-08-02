import Foundation

enum IngestSourceKind: String, Codable, Sendable {
    case sdCard = "sd_card"
    case externalDrive = "external_drive"
    case localFolder = "local_folder"
    case dragDrop = "drag_drop"
    case manualPicker = "manual_picker"
}

enum IngestSkipReason: String, Codable, Sendable {
    case duplicate
    case sidecar
    case unsupported
    case video
    case hidden
    case systemPath
}

struct IngestSkippedFile: Codable, Sendable, Equatable {
    var path: String
    var reason: IngestSkipReason
}

struct IngestFailedFile: Codable, Sendable, Equatable {
    var path: String
    var error: String
}

struct IngestManifest: Codable, Sendable, Equatable {
    var sourceRoot: String
    var sourceKind: IngestSourceKind
    var discoveredAt: Date
    var filesDiscovered: Int
    var filesImported: Int
    var filesSkipped: [IngestSkippedFile]
    var filesFailed: [IngestFailedFile]
    var exifDateMin: Date?
    var exifDateMax: Date?
    var totalBytes: Int64

    var isComplete: Bool { filesImported + filesSkipped.count + filesFailed.count >= filesDiscovered }

    var summaryLine: String {
        let skipped = filesSkipped.count
        let failed = filesFailed.count
        if failed > 0 {
            return "\(filesImported)/\(filesDiscovered) ready · \(skipped) skipped · \(failed) failed"
        }
        if skipped > 0 {
            return "\(filesImported)/\(filesDiscovered) ready · \(skipped) skipped"
        }
        return "\(filesImported)/\(filesDiscovered) ready"
    }
}

struct IngestDiscovery: Sendable {
    var sourceRoot: URL
    var sourceKind: IngestSourceKind
    var photoURLs: [URL]
    var tasteFolder: URL?
    var manifest: IngestManifest
}
