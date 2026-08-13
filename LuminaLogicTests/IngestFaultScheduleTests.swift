import XCTest
@testable import Lumina

final class IngestFaultScheduleTests: XCTestCase {

    func testD35_cardDiskFullFailureShape() {
        let sim = IngestFaultSchedule.simulate(scheduleID: .cardDiskFull, fileCount: 20)
        XCTAssertTrue(sim.writeFailedDiskFull)
        XCTAssertTrue(sim.surface.tableKeepsWorking)
        XCTAssertTrue(IngestFaultSchedule.assertD35Compliant(sim.surface))
        XCTAssertEqual(sim.surface.headline, CopyContract.diskFullHeadline)
        XCTAssertEqual(sim.surface.action, CopyContract.diskFullAction)
    }

    func testD35_cardCorruptFileFailureShape() {
        let sim = IngestFaultSchedule.simulate(scheduleID: .cardCorruptFile, fileCount: 10)
        XCTAssertEqual(sim.skippedCorrupt, 1)
        XCTAssertGreaterThan(sim.importedCount, 0)
        XCTAssertTrue(IngestFaultSchedule.assertD35Compliant(sim.surface))
        XCTAssertEqual(sim.surface.headline, CopyContract.fileDamagedPreviewOnly)
    }

    func testD35_cardTwoCardFailureShape() {
        let sim = IngestFaultSchedule.simulate(scheduleID: .cardTwoCard, fileCount: 20)
        XCTAssertEqual(sim.volumesSeen, 2)
        XCTAssertTrue(IngestFaultSchedule.assertD35Compliant(sim.surface))
        XCTAssertEqual(sim.surface.headline, CopyContract.cardEjectedEarlyHeadline)
    }

    func testD35_noBannedFailureChrome() {
        for schedule in IngestFaultScheduleID.allCases {
            let surface = IngestFaultSchedule.surface(for: schedule)
            XCTAssertFalse(surface.usesModal, "\(schedule.rawValue) must not use modal")
            XCTAssertFalse(surface.usesNSAlert, "\(schedule.rawValue) must not use NSAlert")
            XCTAssertFalse(surface.usesSpinner, "\(schedule.rawValue) must not use spinner")
            XCTAssertFalse(surface.usesProgressBar, "\(schedule.rawValue) must not use progress bar")
        }
    }
}
