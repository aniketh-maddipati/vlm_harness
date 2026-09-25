import XCTest
@testable import Lumina

@MainActor
final class P0ExportPresentationTests: XCTestCase {
    private func summary(completed: Int = 2, pending: Int = 3, interruption: String? = nil) -> P0ExportJobStore.Summary {
        .init(root: URL(fileURLWithPath: "/proof/export"), jobID: UUID(), shootID: UUID(),
              completed: completed, failed: 0, cancelled: 0, pending: pending,
              interruption: interruption, firstFailure: nil)
    }

    func testInterruptedReceiptKeepsWholePlanCounts() {
        let result = summary(interruption: "Destination unavailable")
        let label = P0ExportPresentation.receipt(result)
        XCTAssertTrue(label.contains("2 of 5 written"))
        XCTAssertTrue(label.contains("0 failed"))
        XCTAssertTrue(label.contains("0 cancelled"))
        XCTAssertTrue(label.contains("3 remaining"))
        XCTAssertTrue(label.contains("Destination unavailable"))
    }

    func testKnownCompletedHidesResumeButUnknownAndPartialRemainAvailable() {
        let complete = summary(completed: 5, pending: 0)
        XCTAssertFalse(P0ExportPresentation.shouldOfferResume(knownSummary: complete, jobID: complete.jobID))
        XCTAssertTrue(P0ExportPresentation.shouldOfferResume(knownSummary: nil, jobID: complete.jobID))
        let partial = summary()
        XCTAssertTrue(P0ExportPresentation.shouldOfferResume(knownSummary: partial, jobID: partial.jobID))
        XCTAssertTrue(P0ExportPresentation.shouldOfferResume(knownSummary: complete, jobID: UUID()))
    }

    func testJPEGQualityVisibleAndTIFFOmitsQuality() {
        let localizedQuality = 0.85.formatted(.percent.precision(.fractionLength(0)))
        XCTAssertEqual(P0ExportPresentation.settings(.init(format: .jpeg, longEdge: 2048, quality: 0.85)),
                       "JPEG · sRGB · 2048 px long edge · \(localizedQuality) quality")
        XCTAssertEqual(P0ExportPresentation.settings(.init(format: .tiff, longEdge: 0, quality: 0.85)),
                       "TIFF · ProPhoto RGB · full size")
    }
}
