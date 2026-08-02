import Foundation

enum IngestSourceKind: String, Codable, Sendable {
    case sdCard = "sd_card"
    case externalDrive = "external_drive"
    case iCloud = "icloud"
    case iPhone = "iphone"
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
    case cloudPlaceholder
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
        let kind = sourceKindLabel
        if failed > 0 {
            return "\(filesImported)/\(filesDiscovered) ready · \(kind) · \(skipped) skipped · \(failed) failed"
        }
        if skipped > 0 {
            return "\(filesImported)/\(filesDiscovered) ready · \(kind) · \(skipped) skipped"
        }
        return "\(filesImported)/\(filesDiscovered) ready · \(kind)"
    }

    private var sourceKindLabel: String { sourceKind.displayLabel }
}

struct IngestDiscovery: Sendable {
    var sourceRoot: URL
    var sourceKind: IngestSourceKind
    var photoURLs: [URL]
    var tasteFolder: URL?
    var manifest: IngestManifest
}

extension IngestSourceKind {
    var displayLabel: String {
        switch self {
        case .sdCard: "SD card"
        case .externalDrive: "external drive"
        case .iCloud: "iCloud"
        case .iPhone: "iPhone"
        case .localFolder: "folder"
        case .dragDrop: "drop"
        case .manualPicker: "import"
        }
    }
}
