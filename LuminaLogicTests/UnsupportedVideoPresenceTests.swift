import XCTest
@testable import Lumina

@MainActor
final class UnsupportedVideoPresenceTests: XCTestCase {

    func testUnsupportedVideoIsNotPhoneAndDoesNotOpenInspect() {
        let id = UUID()
        let session = P0SessionModel()
        session.assets = [
            AssetRecord(
                id: id,
                sourceKey: "v-\(id.uuidString)",
                source: SourceReference(
                    originalPath: "/proof/clip.MOV",
                    relativePath: "clip.MOV",
                    volumeID: "PROOF",
                    availability: .available
                ),
                filename: "clip.MOV",
                mediaKind: .unsupportedVideo
            )
        ]
        session.focusedAssetID = id
        XCTAssertTrue(session.assets[0].isUnsupportedVideo)
        XCTAssertFalse(session.isPhoneFrame(id))
        session.openFocusedPhotograph()
        XCTAssertNil(session.inspectingAssetID, "Develop/inspect stay locked for video presence")
    }

    func testMomentMixIgnoresLockedVideoRows() {
        let session = P0SessionModel()
        let cam = UUID()
        let phone = UUID()
        let video = UUID()
        session.assets = [
            AssetRecord(
                id: cam,
                sourceKey: "c",
                source: SourceReference(
                    originalPath: "/proof/a.ARW", relativePath: "a.ARW",
                    volumeID: "PROOF", availability: .available
                ),
                filename: "a.ARW",
                capturedAt: Date(timeIntervalSince1970: 1),
                sensedIsPhone: false
            ),
            AssetRecord(
                id: phone,
                sourceKey: "p",
                source: SourceReference(
                    originalPath: "/proof/b.HEIC", relativePath: "b.HEIC",
                    volumeID: "PROOF", availability: .available
                ),
                filename: "b.HEIC",
                capturedAt: Date(timeIntervalSince1970: 2),
                sensedIsPhone: true
            ),
            AssetRecord(
                id: video,
                sourceKey: "v",
                source: SourceReference(
                    originalPath: "/proof/c.MOV", relativePath: "c.MOV",
                    volumeID: "PROOF", availability: .available
                ),
                filename: "c.MOV",
                capturedAt: Date(timeIntervalSince1970: 3),
                mediaKind: .unsupportedVideo
            ),
        ]
        let chapter = try! XCTUnwrap(session.chapters.first)
        XCTAssertEqual(session.momentMixLine(chapter), "1 camera · 1 phone")
        XCTAssertEqual(chapter.assetIDs.count, 3, "video keeps its place in the chapter sequence")
    }

    func testToolbarCountsVideoPresenceSeparately() {
        var status = ContactSheetPreparationStatus()
        status.assetCount = 3
        status.videoPresenceCount = 1
        status.unsupportedCount = 0
        XCTAssertTrue(status.toolbarLine.contains("1 video"))
        XCTAssertFalse(status.toolbarLine.contains("unsupported"))
    }
}
