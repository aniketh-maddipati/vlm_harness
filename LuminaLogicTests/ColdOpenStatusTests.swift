import Foundation
import XCTest
@testable import Lumina

/// What a cold catalog says about itself while it is still preparing.
///
/// The backlog recorded a cold open reporting `previews 0/N` while extraction ran,
/// and asked whether that is warm-up to surface honestly or a real miss. Measured
/// on the 27-frame elastic card: the sheet opens at ~10 ms with nothing extracted,
/// the first sixteen previews land at ~380 ms and the rest at ~500 ms. The count
/// was truthful the whole way — it is warm-up, not a miss.
///
/// What was wrong was the copy. At the moment the sheet appears, `previews 0/27`
/// reads as a stall rather than as work starting, so the count now waits until
/// there is a count worth reporting.
final class ColdOpenStatusTests: XCTestCase {

    // MARK: - The line itself

    func testPreparingWithNothingReadyDoesNotReportZero() {
        var status = ContactSheetPreparationStatus()
        status.assetCount = 27
        status.isPreparingPreviews = true

        XCTAssertEqual(status.toolbarLine, "27 photos · previews…")
        XCTAssertFalse(
            status.toolbarLine.contains("0/27"),
            "an opening sheet must not read as a stalled one"
        )
    }

    func testTheCountAppearsAsSoonAsThereIsOne() {
        var status = ContactSheetPreparationStatus()
        status.assetCount = 27
        status.isPreparingPreviews = true
        status.previewReadyCount = 16

        XCTAssertEqual(status.toolbarLine, "27 photos · previews 16/27")
    }

    func testFinishedPreparationReportsTheTotal() {
        var status = ContactSheetPreparationStatus()
        status.assetCount = 27
        status.previewReadyCount = 27

        XCTAssertEqual(status.toolbarLine, "27 photos · 27 previews")
    }

    // MARK: - A real cold open

    /// Copies real frames into an untouched folder, so nothing is cataloged and
    /// no preview exists, and watches what the sheet says from open to finished.
    func testColdOpenReachesEveryPreviewAndNeverReportsZeroOfN() async throws {
        let home = NSHomeDirectory()
        let source = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["LUMINA_RAW_DIR"]
                ?? home + "/LuminaFixtures/card-elastic-v4/frames",
            isDirectory: true
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: source.path),
            "no fixture card to open cold"
        )

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cold-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }

        let frames = try FileManager.default
            .contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            .filter { ["ARW", "HEIC", "JPG", "JPEG"].contains($0.pathExtension.uppercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try XCTSkipIf(frames.isEmpty, "no frames in the fixture folder")
        for url in frames {
            try FileManager.default.copyItem(
                at: url,
                to: folder.appendingPathComponent(url.lastPathComponent)
            )
        }

        var lines: [String] = []
        var counts: [Int] = []
        var finalStatus: ContactSheetPreparationStatus?
        for await event in ContactSheetPreparation.openFolder(
            folder,
            shootName: folder.lastPathComponent
        ) {
            let status: ContactSheetPreparationStatus?
            switch event {
            case .opened(_, let s), .status(let s), .assetsReplaced(_, let s),
                 .assetsInserted(_, let s), .previewsUpdated(_, let s), .metadataMerged(_, let s):
                status = s
            case .failed(let message):
                XCTFail("cold open failed: \(message)")
                status = nil
            }
            guard let status else { continue }
            lines.append(status.toolbarLine)
            counts.append(status.previewReadyCount)
            finalStatus = status
        }

        let status = try XCTUnwrap(finalStatus, "the stream produced no status at all")
        XCTAssertEqual(
            status.previewReadyCount, frames.count,
            "a cold open left \(frames.count - status.previewReadyCount) frames without a preview"
        )
        XCTAssertFalse(status.isPreparingPreviews, "preparation never finished")
        XCTAssertEqual(status.toolbarLine, "\(frames.count) photos · \(frames.count) previews")

        // The count only ever rises.
        XCTAssertEqual(counts, counts.sorted(), "the preview count went backwards: \(counts)")
        // And it is never announced as a fraction of nothing.
        for line in lines {
            XCTAssertFalse(
                line.contains("previews 0/"),
                "a preparing sheet reported a zero fraction: \(line) — full sequence \(lines)"
            )
        }
    }
}
