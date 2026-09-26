import XCTest
@testable import Lumina

@MainActor
final class ElasticChronologyTests: XCTestCase {
    func testBoundariesFollowExistingChaptersAndDisplayedOrder() {
        let a = UUID(), b = UUID(), c = UUID()
        let first = ShootChapter(id: "first", startedAt: Date(timeIntervalSince1970: 100), assetIDs: [a, b], bursts: [])
        let second = ShootChapter(id: "second", startedAt: nil, assetIDs: [c], bursts: [])
        let marks = ElasticChronology.boundaries(orderedIDs: [b, a, c], chapters: [first, second], chronological: true)
        XCTAssertEqual(marks[b], first)
        XCTAssertNil(marks[a])
        XCTAssertEqual(marks[c], second)
        XCTAssertEqual(ElasticChronology.label(for: second), "Undated")
    }

    func testManualSetDoesNotClaimChronology() {
        let id = UUID()
        let chapter = ShootChapter(id: "chapter", startedAt: Date(), assetIDs: [id], bursts: [])
        XCTAssertTrue(ElasticChronology.boundaries(orderedIDs: [id], chapters: [chapter], chronological: false).isEmpty)
        let layout = ElasticChronology.placement(chapters: [chapter], chronological: false)
        XCTAssertTrue(layout.nodes.isEmpty)
    }

    func testUnknownAssetsDoNotInventChapterOrTimestamp() {
        let id = UUID(), missing = UUID()
        let chapter = ShootChapter(id: "chapter", startedAt: nil, assetIDs: [id], bursts: [])
        let marks = ElasticChronology.boundaries(orderedIDs: [missing, id], chapters: [chapter], chronological: true)
        XCTAssertNil(marks[missing])
        XCTAssertEqual(marks[id]?.startedAt, nil)
        XCTAssertEqual(marks[id]?.id, chapter.id)
    }

    func testNavigationTracksLeadingChapterThroughGapsAndReverseScrolling() {
        let first = CGRect(x: 0, y: -180, width: 600, height: 250)
        let second = CGRect(x: 0, y: 70, width: 600, height: 200)
        XCTAssertEqual(ElasticChronology.activeChapter(frames: ["a": first, "b": second]), "a")
        XCTAssertEqual(ElasticChronology.activeChapter(frames: [
            "a": first.offsetBy(dx: 0, dy: -80), "b": second.offsetBy(dx: 0, dy: -80)
        ]), "b")
        XCTAssertEqual(ElasticChronology.activeChapter(frames: ["a": first, "b": second]), "a")
        XCTAssertEqual(ElasticChronology.activeChapter(frames: ["a": CGRect(x: 0, y: 20, width: 600, height: 200)]), "a")
        XCTAssertNil(ElasticChronology.activeChapter(frames: [:]))
    }

    func testChronologyMarkerDoesNotMoveFocusOrSelection() {
        let session = P0SessionModel()
        let id = UUID()
        session.focusedAssetID = id
        session.selectedAssetIDs = [id]
        session.chronologyViewportChapterID = "visible-chapter"
        XCTAssertEqual(session.focusedAssetID, id)
        XCTAssertEqual(session.selectedAssetIDs, [id])
        XCTAssertEqual(session.uiTestSnapshot().chronologyViewportChapterID, "visible-chapter")
    }

    func testUndatedChaptersSitAtEndWithUndatedLabel() {
        let early = UUID(), late = UUID(), undated = UUID()
        let undatedChapter = ShootChapter(
            id: "undated", startedAt: nil, assetIDs: [undated], bursts: []
        )
        let first = ShootChapter(
            id: "first",
            startedAt: Date(timeIntervalSince1970: 1_000),
            assetIDs: [early],
            bursts: []
        )
        let second = ShootChapter(
            id: "second",
            startedAt: Date(timeIntervalSince1970: 3_600),
            assetIDs: [late],
            bursts: []
        )
        let ordered = ElasticChronology.orderedForAxis([undatedChapter, second, first])
        XCTAssertEqual(ordered.map(\.id), ["first", "second", "undated"])
        XCTAssertEqual(ElasticChronology.label(for: undatedChapter), "Undated")

        let layout = ElasticChronology.placement(
            chapters: [undatedChapter, second, first],
            chronological: true
        )
        XCTAssertEqual(layout.nodes.map(\.chapterID), ["first", "second", "undated"])
        XCTAssertEqual(layout.nodes.last?.label, "Undated")
        XCTAssertTrue(layout.nodes.last?.isUndated == true)
    }

    func testShortWindowUsesOrderSpacingAndSecondLevelLabels() {
        let a = UUID(), b = UUID(), c = UUID()
        let t0 = Date(timeIntervalSince1970: 10_000)
        let chapters = [
            ShootChapter(id: "a", startedAt: t0, assetIDs: [a], bursts: []),
            ShootChapter(id: "b", startedAt: t0.addingTimeInterval(30), assetIDs: [b], bursts: []),
            ShootChapter(id: "c", startedAt: t0.addingTimeInterval(90), assetIDs: [c], bursts: []),
        ]
        XCTAssertTrue(ElasticChronology.isShortWindow(chapters: chapters))
        let layout = ElasticChronology.placement(
            chapters: chapters, chronological: true, scale: ElasticLayout.ChronAxis.unitLength
        )
        XCTAssertTrue(layout.shortWindow)
        for node in layout.nodes {
            XCTAssertEqual(node.label.split(separator: ":").count, 3, node.label)
            XCTAssertFalse(node.label.contains("·"))
        }
        for index in 1..<layout.nodes.count {
            let gap = layout.nodes[index].position - layout.nodes[index - 1].position
            XCTAssertGreaterThanOrEqual(gap, ElasticLayout.ChronAxis.floorGap - 0.0001)
        }
    }

    func testLongShootStaysProportionalWithFloorGap() {
        let a = UUID(), b = UUID(), c = UUID()
        let t0 = Date(timeIntervalSince1970: 20_000)
        let chapters = [
            ShootChapter(id: "a", startedAt: t0, assetIDs: [a], bursts: []),
            ShootChapter(id: "b", startedAt: t0.addingTimeInterval(30 * 60), assetIDs: [b], bursts: []),
            ShootChapter(id: "c", startedAt: t0.addingTimeInterval(2 * 60 * 60), assetIDs: [c], bursts: []),
        ]
        XCTAssertFalse(ElasticChronology.isShortWindow(chapters: chapters))
        let layout = ElasticChronology.placement(
            chapters: chapters, chronological: true, scale: ElasticLayout.ChronAxis.unitLength
        )
        XCTAssertFalse(layout.shortWindow)
        // Middle node closer to start than end (30 min of 2 h).
        XCTAssertLessThan(layout.nodes[1].position, layout.nodes[2].position * 0.5 + 0.01)
        for node in layout.nodes {
            XCTAssertTrue(node.label.contains("·"), node.label)
        }
        for index in 1..<layout.nodes.count {
            let gap = layout.nodes[index].position - layout.nodes[index - 1].position
            XCTAssertGreaterThanOrEqual(gap, ElasticLayout.ChronAxis.floorGap - 0.0001)
        }
    }

    func testPinchScaleStretchesContentLengthOnly() {
        let a = UUID(), b = UUID()
        let t0 = Date(timeIntervalSince1970: 30_000)
        let chapters = [
            ShootChapter(id: "a", startedAt: t0, assetIDs: [a], bursts: []),
            ShootChapter(id: "b", startedAt: t0.addingTimeInterval(60 * 60), assetIDs: [b], bursts: []),
        ]
        let base = ElasticChronology.placement(
            chapters: chapters, chronological: true, scale: ElasticLayout.ChronAxis.unitLength
        )
        let zoomed = ElasticChronology.placement(
            chapters: chapters, chronological: true, scale: 2
        )
        XCTAssertGreaterThan(zoomed.contentLength, base.contentLength)
        XCTAssertEqual(base.shortWindow, zoomed.shortWindow)
        XCTAssertEqual(base.nodes.map(\.chapterID), zoomed.nodes.map(\.chapterID))
    }

    func testCrowdedProportionalNodesTriggerShortWindow() {
        let a = UUID(), b = UUID(), c = UUID()
        let t0 = Date(timeIntervalSince1970: 40_000)
        let chapters = [
            ShootChapter(id: "a", startedAt: t0, assetIDs: [a], bursts: []),
            ShootChapter(id: "b", startedAt: t0.addingTimeInterval(5), assetIDs: [b], bursts: []),
            ShootChapter(id: "c", startedAt: t0.addingTimeInterval(3 * 60 * 60), assetIDs: [c], bursts: []),
        ]
        XCTAssertTrue(ElasticChronology.isShortWindow(chapters: chapters))
        let layout = ElasticChronology.placement(chapters: chapters, chronological: true)
        XCTAssertTrue(layout.shortWindow)
    }

    func testSameHourBreaksIntoMinuteTicks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let hour = calendar.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 14, minute: 5))!
        let chapters = [
            ShootChapter(id: "a", startedAt: hour, assetIDs: [UUID()], bursts: []),
            ShootChapter(id: "b", startedAt: hour.addingTimeInterval(10 * 60), assetIDs: [UUID()], bursts: []),
            ShootChapter(id: "c", startedAt: hour.addingTimeInterval(25 * 60), assetIDs: [UUID()], bursts: []),
        ]
        let layout = ElasticChronology.placement(chapters: chapters, chronological: true)
        XCTAssertEqual(layout.resolution, .minutes)
        let labeled = layout.ticks.filter { $0.major && !$0.label.isEmpty }
        XCTAssertGreaterThan(labeled.count, 1, "the hour is a ruler, not one stamp")
        for tick in labeled {
            XCTAssertEqual(tick.label.split(separator: ":").count, 2, tick.label)
            XCTAssertFalse(tick.label.contains("·"), tick.label)
        }
    }

    func testSameMinuteBreaksIntoSecondTicks() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_040)
        let chapters = [
            ShootChapter(id: "a", startedAt: t0, assetIDs: [UUID()], bursts: []),
            ShootChapter(id: "b", startedAt: t0.addingTimeInterval(20), assetIDs: [UUID()], bursts: []),
        ]
        let layout = ElasticChronology.placement(chapters: chapters, chronological: true)
        XCTAssertEqual(layout.resolution, .seconds)
        let labeled = layout.ticks.filter { $0.major && !$0.label.isEmpty }
        XCTAssertGreaterThanOrEqual(labeled.count, 1)
        XCTAssertEqual(labeled.first?.label.split(separator: ":").count, 3)
    }

    func testPinchOnALongDayRefinesHoursToMinutes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let morning = calendar.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 8, minute: 0))!
        let evening = calendar.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 16, minute: 0))!
        let chapters = [
            ShootChapter(id: "a", startedAt: morning, assetIDs: [UUID()], bursts: []),
            ShootChapter(id: "b", startedAt: evening, assetIDs: [UUID()], bursts: []),
        ]
        let wide = ElasticChronology.placement(
            chapters: chapters, chronological: true, scale: ElasticLayout.ChronAxis.unitLength
        )
        let tight = ElasticChronology.placement(chapters: chapters, chronological: true, scale: 4)
        XCTAssertEqual(wide.resolution, .hours)
        XCTAssertEqual(tight.resolution, .minutes)
        XCTAssertGreaterThan(tight.ticks.count, wide.ticks.count)
    }
}
