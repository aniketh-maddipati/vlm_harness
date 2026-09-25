import Foundation

@MainActor
enum P0ExportPresentation {
    static func settings(_ settings: P0ExportSettings) -> String {
        let format = settings.format == .jpeg ? "JPEG · sRGB" : "TIFF · ProPhoto RGB"
        let size = settings.longEdge == 0 ? "full size" : "\(settings.longEdge) px long edge"
        let quality = settings.format == .jpeg ? " · \(settings.quality.formatted(.percent.precision(.fractionLength(0)))) quality" : ""
        return "\(format) · \(size)\(quality)"
    }

    static func shouldOfferResume(knownSummary: P0ExportJobStore.Summary?, jobID: UUID) -> Bool {
        guard let knownSummary, knownSummary.jobID == jobID else { return true }
        return !knownSummary.allCompleted
    }

    static func receipt(_ summary: P0ExportJobStore.Summary) -> String {
        let counts = CopyContract.exportReceipt(written: summary.completed, total: summary.total,
                                                failed: summary.failed, cancelled: summary.cancelled)
            + " · \(summary.pending) remaining"
        return summary.interruption.map { counts + " · " + $0 } ?? counts
    }
}
