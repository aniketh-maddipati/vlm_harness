import Foundation

// MARK: - Ingest fault schedules (fixture-manifest §2 — logic only, no UI)

/// Manifest-bound hostile schedules — do not add ids here without a fixture-manifest row.
enum IngestFaultScheduleID: String, CaseIterable, Sendable {
    case cardDiskFull = "card-disk-full"
    case cardTwoCard = "card-two-card"
    case cardCorruptFile = "card-corrupt-file"
}

/// D35 failure surface — one sentence, one action, table keeps working; no banned chrome.
struct IngestFaultSurface: Equatable, Sendable {
    var scheduleID: IngestFaultScheduleID
    var headline: String
    var action: String
    var tableKeepsWorking: Bool
    var usesModal: Bool
    var usesSpinner: Bool
    var usesProgressBar: Bool
    var usesNSAlert: Bool
}

struct IngestImportSimulation: Equatable, Sendable {
    var importedCount: Int
    var skippedCorrupt: Int
    var volumesSeen: Int
    var writeFailedDiskFull: Bool
    var surface: IngestFaultSurface
}

/// Pure schedule evaluator for harness + logic tests (CP2 / F06).
enum IngestFaultSchedule {
    static func surface(for scheduleID: IngestFaultScheduleID) -> IngestFaultSurface {
        switch scheduleID {
        case .cardDiskFull:
            return IngestFaultSurface(
                scheduleID: scheduleID,
                headline: CopyContract.diskFullHeadline,
                action: CopyContract.diskFullAction,
                tableKeepsWorking: true,
                usesModal: false,
                usesSpinner: false,
                usesProgressBar: false,
                usesNSAlert: false
            )
        case .cardTwoCard:
            return IngestFaultSurface(
                scheduleID: scheduleID,
                headline: CopyContract.cardEjectedEarlyHeadline,
                action: CopyContract.cardEjectedEarlyAction,
                tableKeepsWorking: true,
                usesModal: false,
                usesSpinner: false,
                usesProgressBar: false,
                usesNSAlert: false
            )
        case .cardCorruptFile:
            return IngestFaultSurface(
                scheduleID: scheduleID,
                headline: CopyContract.fileDamagedPreviewOnly,
                action: CopyContract.fileDamagedPreviewOnlyAction,
                tableKeepsWorking: true,
                usesModal: false,
                usesSpinner: false,
                usesProgressBar: false,
                usesNSAlert: false
            )
        }
    }

    /// Simulated ingest outcome for a schedule — no network, no UI widgets.
    static func simulate(scheduleID: IngestFaultScheduleID, fileCount: Int = 12) -> IngestImportSimulation {
        let base = surface(for: scheduleID)
        switch scheduleID {
        case .cardDiskFull:
            return IngestImportSimulation(
                importedCount: max(0, fileCount - 1),
                skippedCorrupt: 0,
                volumesSeen: 1,
                writeFailedDiskFull: true,
                surface: base
            )
        case .cardTwoCard:
            return IngestImportSimulation(
                importedCount: fileCount / 2,
                skippedCorrupt: 0,
                volumesSeen: 2,
                writeFailedDiskFull: false,
                surface: base
            )
        case .cardCorruptFile:
            return IngestImportSimulation(
                importedCount: max(0, fileCount - 1),
                skippedCorrupt: 1,
                volumesSeen: 1,
                writeFailedDiskFull: false,
                surface: base
            )
        }
    }

    static func assertD35Compliant(_ surface: IngestFaultSurface) -> Bool {
        !surface.headline.isEmpty
            && !surface.action.isEmpty
            && surface.tableKeepsWorking
            && !surface.usesModal
            && !surface.usesSpinner
            && !surface.usesProgressBar
            && !surface.usesNSAlert
    }
}
