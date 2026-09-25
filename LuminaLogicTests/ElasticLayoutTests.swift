import XCTest
@testable import Lumina

/// Checkpoint 03 — the layout numbers and moment copy the design fixes.
@MainActor
final class ElasticLayoutTests: XCTestCase {

    // MARK: - Gap steps

    func testGapHeightUsesTheThreeQuantizedSteps() {
        XCTAssertEqual(ElasticLayout.gapHeight(after: 0), 14, "every moment after the first is separated")
        XCTAssertEqual(ElasticLayout.gapHeight(after: 9 * 60), 14, "under 10 min still parts the rows")
        XCTAssertEqual(ElasticLayout.gapHeight(after: 10 * 60), 14)
        XCTAssertEqual(ElasticLayout.gapHeight(after: 24 * 60), 14)
        XCTAssertEqual(ElasticLayout.gapHeight(after: 25 * 60), 40)
        XCTAssertEqual(ElasticLayout.gapHeight(after: 59 * 60), 40)
        XCTAssertEqual(ElasticLayout.gapHeight(after: 60 * 60), 64)
        XCTAssertEqual(ElasticLayout.gapHeight(after: 6 * 60 * 60), 64, "the longest step does not keep growing")
    }

    func testGapHeightIsMonotonic() {
        var previous = ElasticLayout.gapHeight(after: 0)
        for minutes in stride(from: 0, through: 180, by: 5) {
            let height = ElasticLayout.gapHeight(after: TimeInterval(minutes) * 60)
            XCTAssertGreaterThanOrEqual(height, previous, "a longer pause must never narrow the gap")
            previous = height
        }
    }

    // MARK: - Gap label

    func testGapLabelFormatting() {
        XCTAssertNil(ElasticLayout.gapLabel(for: 9 * 60), "no label below the first threshold")
        XCTAssertEqual(ElasticLayout.gapLabel(for: 18 * 60), "+ 18 min")
        XCTAssertEqual(ElasticLayout.gapLabel(for: 60 * 60), "+ 1 h")
        XCTAssertEqual(ElasticLayout.gapLabel(for: 135 * 60), "+ 2 h 15 min")
    }

    // MARK: - Tiles

    func testTileAndFilmstripSizesMatchTheDesign() {
        XCTAssertEqual(ElasticLayout.tile, 168)
        XCTAssertEqual(ElasticLayout.tileInOpenBurst, 128)
        XCTAssertEqual(ElasticLayout.filmstripHeight, 92)
        XCTAssertEqual(ElasticLayout.filmstripFocusedTile, CGSize(width: 96, height: 64))
        XCTAssertEqual(ElasticLayout.filmstripTile, CGSize(width: 72, height: 48))
        XCTAssertEqual(ElasticLayout.filmstripMomentGap, 20)
        XCTAssertEqual(ElasticLayout.versionColumnWidth, 144)
        XCTAssertEqual(ElasticLayout.developDrawerWidth, 256)
    }

    func testOutOpacityIsTheExistingRejectDimLaw() {
        XCTAssertEqual(ElasticLayout.outOpacity, 0.45, accuracy: 1e-9)
        XCTAssertEqual(
            ElasticLayout.outOpacity,
            HiFiTokens.Color.rejectDimOpacity,
            "rejects dim by one law, not two"
        )
    }

    // MARK: - Header and moment copy

    private func makeAsset(
        id: UUID = UUID(),
        filename: String = "DSC0001.ARW",
        capturedAt: Date? = nil,
        source: RecipeSource = .shot,
        cull: CullDecision = .undecided,
        sensedIsPhone: Bool? = nil,
        manualIsPhone: Bool? = nil,
        captureMake: String? = nil,
        captureModel: String? = nil
    ) -> AssetRecord {
        AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: "/proof/\(filename)",
                relativePath: filename,
                volumeID: "PROOF",
                availability: .available
            ),
            filename: filename,
            cull: cull,
            capturedAt: capturedAt,
            recipeSource: source,
            captureMake: captureMake,
            captureModel: captureModel,
            sensedIsPhone: sensedIsPhone,
            manualIsPhone: manualIsPhone
        )
    }

    private func makePhoneAsset(
        filename: String,
        capturedAt: Date?
    ) -> AssetRecord {
        makeAsset(
            filename: filename,
            capturedAt: capturedAt,
            sensedIsPhone: true,
            captureMake: "apple",
            captureModel: "iphone 16 pro"
        )
    }

    func testHeaderLineMatchesTheSpecifiedShape() {
        let session = P0SessionModel()
        session.assets = [
            makeAsset(filename: "a.ARW", capturedAt: Date(timeIntervalSince1970: 1_000_000)),
            makeAsset(filename: "b.ARW", capturedAt: Date(timeIntervalSince1970: 1_000_001), source: .auto),
            makeAsset(filename: "c.ARW", capturedAt: Date(timeIntervalSince1970: 1_000_002), source: .hand),
            makeAsset(filename: "d.ARW", capturedAt: Date(timeIntervalSince1970: 1_000_003), source: .sidecar),
        ]

        let line = session.elasticHeaderLine
        XCTAssertTrue(line.hasPrefix("4 frames · "), line)
        XCTAssertTrue(line.contains(" · 1 as shot · 1 auto · 2 yours · "), line)
        XCTAssertTrue(line.hasSuffix("? keys"), line)
    }

    func testMomentCountLineSingularizesOneFrame() {
        let session = P0SessionModel()
        let solo = makeAsset(filename: "solo.ARW", capturedAt: Date(timeIntervalSince1970: 2_000_000))
        session.assets = [solo]
        let chapter = try? XCTUnwrap(session.chapters.first)
        XCTAssertEqual(session.momentCountLine(chapter!), "1 frame", "one frame is not '1 frames'")
    }

    func testPhoneFramesAreCountedSeparately() {
        let session = P0SessionModel()
        session.assets = [
            makeAsset(filename: "a.ARW", capturedAt: Date(timeIntervalSince1970: 3_000_000)),
            makePhoneAsset(filename: "b.HEIC", capturedAt: Date(timeIntervalSince1970: 3_000_001)),
        ]
        let chapter = session.chapters.first
        XCTAssertNotNil(chapter)
        XCTAssertEqual(session.momentMixLine(chapter!), "1 camera · 1 phone")
        XCTAssertFalse(
            session.momentCountLine(chapter!).contains("phone"),
            "the span line counts frames and bursts; the mix line counts bodies"
        )
    }

    func testManualPhoneMarkSharesTheSensedTag() {
        let session = P0SessionModel()
        let cameraJPEG = makeAsset(
            filename: "IMG_0001.JPG",
            capturedAt: Date(timeIntervalSince1970: 3_000_100),
            sensedIsPhone: false,
            captureMake: "sony",
            captureModel: "ilce-7m4"
        )
        session.assets = [cameraJPEG]
        XCTAssertFalse(session.isPhoneFrame(cameraJPEG.id))
        XCTAssertTrue(session.toggleManualPhoneBody(cameraJPEG.id))
        XCTAssertTrue(session.isPhoneFrame(cameraJPEG.id), "hand mark uses the same phone tag")
        XCTAssertEqual(session.momentMixLine(session.chapters[0]), "1 phone")
        XCTAssertTrue(session.toggleManualPhoneBody(cameraJPEG.id))
        XCTAssertFalse(session.isPhoneFrame(cameraJPEG.id), "toggling again clears back to sensed")
    }

    func testClassifyPhoneMarksTheRunAndTheNextPressClearsIt() {
        let session = P0SessionModel()
        let camera = makeAsset(filename: "a.ARW", capturedAt: Date(timeIntervalSince1970: 3_000_000))
        let phone = makePhoneAsset(filename: "b.HEIC", capturedAt: Date(timeIntervalSince1970: 3_000_000.4))
        session.assets = [camera, phone]
        XCTAssertEqual(session.chapters[0].bursts.count, 2, "a phone frame does not join the camera burst")

        XCTAssertEqual(session.classifyPhone([camera.id]), 1)
        XCTAssertTrue(session.isPhoneFrame(camera.id))
        XCTAssertEqual(session.chapters[0].bursts.count, 1, "marked phone, they are one run")

        XCTAssertEqual(session.classifyPhone([camera.id, phone.id]), 2)
        XCTAssertFalse(session.isPhoneFrame(camera.id))
        XCTAssertFalse(session.isPhoneFrame(phone.id))
    }

    func testLightWordTracksTheHour() {
        let session = P0SessionModel()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        func chapter(atHour hour: Int) -> ShootChapter {
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
            return ShootChapter(id: "c", startedAt: date, assetIDs: [], bursts: [])
        }
        XCTAssertEqual(session.momentLightWord(chapter(atHour: 3)), "before sunrise")
        XCTAssertEqual(session.momentLightWord(chapter(atHour: 12)), "midday")
        XCTAssertEqual(session.momentLightWord(chapter(atHour: 19)), "golden hour")
        XCTAssertEqual(session.momentLightWord(chapter(atHour: 21)), "after sunset")
    }

    // MARK: - Routes

    func testFocusIsARouteAndKeepsTheCursor() {
        let session = P0SessionModel()
        let id = UUID()
        session.assets = [makeAsset(id: id)]
        // A session with no shoot sits on `.open`; the table is where an opened shoot lands.
        session.route = .time
        session.setFocus(id)
        XCTAssertEqual(session.route, .time, "moving the cursor is not opening a photograph")
        XCTAssertNil(session.inspectingAssetID, "the table route has nothing open")

        session.openFocusedPhotograph()
        XCTAssertEqual(session.route, .focus)
        XCTAssertEqual(session.inspectingAssetID, id)

        session.closeInspection()
        XCTAssertEqual(session.route, .time)
        XCTAssertNil(session.inspectingAssetID)
        XCTAssertEqual(session.focusedAssetID, id, "leaving focus keeps the cursor")
    }

    func testAutoButtonSubLabelReflectsWhatAutoWouldTouch() {
        let session = P0SessionModel()
        let a = UUID(), b = UUID()
        session.assets = [makeAsset(id: a), makeAsset(id: b, source: .hand)]
        XCTAssertEqual(session.autoButtonSubLabel, "all · 1", "only the as-shot frame is eligible")

        session.assets = [makeAsset(id: a, source: .hand), makeAsset(id: b, source: .auto)]
        XCTAssertEqual(session.autoButtonSubLabel, "nothing as shot")
    }
}
