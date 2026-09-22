import XCTest
@testable import Lumina

/// The chapter arrangement behind `session.chapters`.
///
/// The table reads it once per row and several times per gap. It is a pure
/// function of `assets`, so it is cached with `assets` and must go stale the
/// moment `assets` changes — the same contract as the asset index.
@MainActor
final class P0SessionChaptersCacheTests: XCTestCase {

    private func makeAsset(
        filename: String,
        capturedAt: Date?
    ) -> AssetRecord {
        let id = UUID()
        var asset = AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: "/proof/\(filename)",
                relativePath: filename,
                volumeID: "PROOF",
                availability: .available
            ),
            filename: filename,
            cull: .undecided
        )
        asset.capturedAt = capturedAt
        return asset
    }

    private func shoot(momentsApartMinutes minutes: Double, count: Int) -> [AssetRecord] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            makeAsset(
                filename: String(format: "DSC%04d.ARW", index + 1),
                capturedAt: base.addingTimeInterval(Double(index) * minutes * 60)
            )
        }
    }

    func testRepeatedReadsReturnTheSameArrangement() {
        let session = P0SessionModel()
        session.assets = shoot(momentsApartMinutes: 12, count: 6)
        let first = session.chapters
        let second = session.chapters
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.count, 6, "12 minutes apart is past the walk gap, so every frame is its own moment")
    }

    func testArrangementFollowsAssets() {
        let session = P0SessionModel()
        session.assets = shoot(momentsApartMinutes: 12, count: 4)
        XCTAssertEqual(session.chapters.count, 4)

        session.assets = shoot(momentsApartMinutes: 0.5, count: 4)
        XCTAssertEqual(session.chapters.count, 1, "30 s apart is one moment — the cache must not survive the change")

        session.assets.append(makeAsset(
            filename: "DSC9999.ARW",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + 3 * 3600)
        ))
        XCTAssertEqual(session.chapters.count, 2, "an in-place append is a change too")
    }

    func testGapIntervalReadsTheCachedArrangement() {
        let session = P0SessionModel()
        session.assets = shoot(momentsApartMinutes: 12, count: 3)
        XCTAssertEqual(session.gapInterval(after: 0), 12 * 60)
        XCTAssertNil(session.gapInterval(after: 2), "no moment after the last")
    }

    func testCaptureNameParseIsStableAcrossManyCalls() {
        // The version-suffix regex is compiled once; parsing must not depend on it.
        for index in 0..<2_000 {
            let name = CaptureName.parse("DSC0\(8000 + index)-2.ARW")
            XCTAssertEqual(name.sequence, 8000 + index)
            XCTAssertEqual(name.stemKey, "dsc0\(8000 + index)")
        }
    }
}
