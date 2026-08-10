import XCTest
@testable import Lumina

@MainActor
final class TableTests: XCTestCase {

    func testResponsivePageSizeEdgeCases() {
        XCTAssertEqual(TableLayout.responsivePageSize(twoUp: false, availableWidth: 1200), 3)
        XCTAssertEqual(TableLayout.responsivePageSize(twoUp: true, availableWidth: 1600), 2)
        XCTAssertEqual(TableLayout.responsivePageSize(twoUp: false, availableWidth: 0), 3)
        XCTAssertEqual(TableLayout.responsivePageSize(twoUp: false, availableWidth: -100), 3)
    }

    func testComparisonCompressionBoostsFocus() {
        let compression = TableLayout.comparisonCompression(pageSize: 4, hasSelection: true)
        XCTAssertEqual(compression.focusScale, 1.22, accuracy: 0.001)
        XCTAssertLessThan(compression.neighborScale, 1.0)
    }

    func testSceneBreakLabelFormatting() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let part1End = base.addingTimeInterval(8 * 60)
        let part2Start = base.addingTimeInterval(9 * 60)
        let sceneStart = base.addingTimeInterval(60 * 60)
        let g1 = GroupPresentation(
            id: "a",
            title: "Set 1",
            assets: [],
            timeStart: base,
            timeEnd: part1End,
            siblingGroupID: "lane-1",
            siblingPartIndex: 1,
            siblingPartCount: 2
        )
        let g2 = GroupPresentation(
            id: "b",
            title: "Set 1 continued",
            assets: [],
            timeStart: part2Start,
            timeEnd: base.addingTimeInterval(16 * 60),
            siblingGroupID: "lane-1",
            siblingPartIndex: 2,
            siblingPartCount: 2
        )
        let g3 = GroupPresentation(
            id: "c",
            title: "Later scene",
            assets: [],
            timeStart: sceneStart,
            timeEnd: sceneStart.addingTimeInterval(5 * 60)
        )
        let units = TableLayout.swimLaneUnits(from: [g1, g2, g3])
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[1].sceneBreakBefore, "+ 44 min")
        XCTAssertNil(TableLayout.sceneBreakLabel(from: g2, to: g3).flatMap { $0 == "+ 0 min" ? $0 : nil })
        let immediate = GroupPresentation(
            id: "d",
            title: "Immediate",
            assets: [],
            timeStart: part1End.addingTimeInterval(30),
            timeEnd: part1End.addingTimeInterval(60)
        )
        XCTAssertNil(TableLayout.sceneBreakLabel(from: g1, to: immediate))
    }

    func testLaneHeaderUsesFirstPartTimestamp() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let g1 = GroupPresentation(
            id: "a",
            title: "Set 1",
            assets: [],
            timeStart: base,
            timeEnd: base.addingTimeInterval(8 * 60),
            siblingGroupID: "lane-1",
            siblingPartIndex: 1,
            siblingPartCount: 2
        )
        let g2 = GroupPresentation(
            id: "b",
            title: "Set 1 continued",
            assets: [],
            timeStart: base.addingTimeInterval(9 * 60),
            timeEnd: base.addingTimeInterval(16 * 60),
            siblingGroupID: "lane-1",
            siblingPartIndex: 2,
            siblingPartCount: 2
        )
        let units = TableLayout.swimLaneUnits(from: [g1, g2])
        XCTAssertEqual(units[0].laneHeader, CopyContractBuilder.laneTimestamp(from: base))
    }
}
