import XCTest
@testable import Lumina

/// The `id → position` index behind `session.asset(_:)`.
///
/// The table asks for a record by id several times per tile, so the index is
/// what keeps a render pass linear in the shoot rather than quadratic. It is a
/// cache, so the cases that matter are the ones where it could go stale.
@MainActor
final class P0SessionAssetIndexTests: XCTestCase {

    private func makeAsset(
        id: UUID = UUID(),
        filename: String = "DSC0001.ARW",
        cull: CullDecision = .undecided
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
            cull: cull
        )
    }

    func testLookupFindsEveryAssetAndRejectsStrangers() {
        let session = P0SessionModel()
        let ids = (0..<8).map { _ in UUID() }
        session.assets = ids.map { makeAsset(id: $0) }

        for (offset, id) in ids.enumerated() {
            XCTAssertEqual(session.assetIndex(id), offset)
            XCTAssertEqual(session.asset(id)?.id, id)
        }
        XCTAssertNil(session.asset(UUID()), "an id from another shoot is not a hit")
    }

    func testIndexSurvivesReorderingTheSameIDs() {
        let session = P0SessionModel()
        let ids = (0..<5).map { _ in UUID() }
        session.assets = ids.map { makeAsset(id: $0) }
        _ = session.assetIndex(ids[0])  // warm the cache

        session.assets.reverse()

        for (offset, id) in ids.reversed().enumerated() {
            XCTAssertEqual(
                session.assetIndex(id), offset,
                "a reorder keeps every id but moves them — the cache must not survive it"
            )
        }
    }

    func testIndexInvalidatesWhenAnAssetIsRemoved() {
        let session = P0SessionModel()
        let ids = (0..<4).map { _ in UUID() }
        session.assets = ids.map { makeAsset(id: $0) }
        _ = session.assetIndex(ids[3])

        session.assets.removeFirst()

        XCTAssertNil(session.asset(ids[0]), "the removed asset is gone, not stale")
        XCTAssertEqual(session.assetIndex(ids[3]), 2, "survivors shifted down by one")
    }

    /// The case a naive cache gets wrong: mutating a field on an element is a
    /// write to the array, so the index must see it even though no id moved.
    func testMutatingAnElementDoesNotServeAStaleRecord() {
        let session = P0SessionModel()
        let id = UUID()
        session.assets = [makeAsset(id: id, cull: .undecided)]
        XCTAssertEqual(session.asset(id)?.cull, .undecided)

        session.assets[0].cull = .keep

        XCTAssertEqual(
            session.asset(id)?.cull, .keep,
            "the index must hand back the current record, not the one it cached"
        )
        XCTAssertTrue(session.isInFinalSet(id))
    }

    func testLookupAgreesWithALinearScanAcrossMutations() {
        let session = P0SessionModel()
        var ids = (0..<6).map { _ in UUID() }
        session.assets = ids.map { makeAsset(id: $0) }

        func agree(_ note: String) {
            for id in ids {
                let scanned = session.assets.firstIndex(where: { $0.id == id })
                XCTAssertEqual(session.assetIndex(id), scanned, note)
            }
        }

        agree("fresh")
        session.assets.append(makeAsset(id: ids[0]))  // duplicate id, appended last
        agree("after appending a duplicate id")
        session.assets.removeLast()
        ids.removeFirst()
        session.assets.removeFirst()
        agree("after removing the head")
    }
}
