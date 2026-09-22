import XCTest
@testable import Lumina

/// Checkpoint 04 — the flags peek's inference, and `G` taking its picks.
@MainActor
final class ElasticInferredGroupsTests: XCTestCase {

    private func asset(_ id: UUID, offset: TimeInterval, cull: CullDecision = .undecided, ext: String = "ARW") -> AssetRecord {
        AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: "/x/\(id.uuidString).\(ext)",
                relativePath: "\(id.uuidString).\(ext)",
                volumeID: "VOL",
                availability: .available
            ),
            filename: "asset-\(id.uuidString).\(ext)",
            cull: cull,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset)
        )
    }

    private func context(phones: Set<UUID> = []) -> ElasticInferredGroups.Context {
        ElasticInferredGroups.Context(
            isPhone: { phones.contains($0) },
            momentTimeLabel: { _ in "05:58" },
            momentLightWord: { _ in "before sunrise" }
        )
    }

    // MARK: - Groups

    func testBurstLeaderIsTheSharpestOnceMeasured() {
        let ids = (0..<3).map { _ in UUID() }
        let assets = ids.enumerated().map { asset($1, offset: Double($0) * 0.4) }
        let chapters = ShootChapterArrangement.arrange(assets)
        XCTAssertEqual(chapters[0].bursts.count, 1)

        let unmeasured = ElasticInferredGroups.infer(
            chapters: chapters, assets: assets,
            measurements: .init(), context: context()
        )
        XCTAssertEqual(unmeasured.count, 1)
        XCTAssertEqual(unmeasured[0].kind, .sameBurst)
        XCTAssertEqual(unmeasured[0].takeIDs, [ids[0]], "unmeasured: the first frame leads")
        XCTAssertTrue(unmeasured[0].tags.isEmpty, "no `sharpest` claim before measuring")
        XCTAssertEqual(unmeasured[0].reason, "3 frames in 0.8 s at 05:58 · leader is the first frame")
        XCTAssertEqual(unmeasured[0].pick, "1 of 3")

        var measurements = ElasticInferredGroups.Measurements()
        measurements.sharpness = [ids[0]: 0.2, ids[1]: 0.9, ids[2]: 0.5]
        let measured = ElasticInferredGroups.infer(
            chapters: chapters, assets: assets,
            measurements: measurements, context: context()
        )
        XCTAssertEqual(measured[0].takeIDs, [ids[1]])
        XCTAssertEqual(measured[0].tags, [ids[1]: "sharpest"])
        XCTAssertEqual(measured[0].reason, "3 frames in 0.8 s at 05:58 · leader is sharpest")
        XCTAssertEqual(measured[0].takeLine, "G takes 1 (1 of 3)")
    }

    func testSceneTakesTheSinglesAndPhonesStepBack() {
        let ids = (0..<4).map { _ in UUID() }
        let assets = [
            asset(ids[0], offset: 0),
            asset(ids[1], offset: 20),
            asset(ids[2], offset: 45, ext: "HEIC"),
            asset(ids[3], offset: 3600),
        ]
        let chapters = ShootChapterArrangement.arrange(assets)
        XCTAssertEqual(chapters.count, 2)
        let groups = ElasticInferredGroups.infer(
            chapters: chapters, assets: assets,
            measurements: .init(), context: context(phones: [ids[2]])
        )
        XCTAssertEqual(groups.count, 1, "a lone frame in the second moment is no group")
        XCTAssertEqual(groups[0].kind, .sameScene)
        XCTAssertEqual(groups[0].frameIDs, [ids[0], ids[1], ids[2]])
        XCTAssertEqual(groups[0].takeIDs, [ids[0], ids[1]], "the phone frame stays out of the take")
        XCTAssertEqual(groups[0].reason, "3 frames within 45 s · before sunrise · same place, different framing")
        XCTAssertEqual(groups[0].pick, "all")
    }

    func testAllPhoneSceneTakesThemAll() {
        let ids = (0..<2).map { _ in UUID() }
        let assets = [asset(ids[0], offset: 0, ext: "HEIC"), asset(ids[1], offset: 10, ext: "HEIC")]
        let groups = ElasticInferredGroups.infer(
            chapters: ShootChapterArrangement.arrange(assets), assets: assets,
            measurements: .init(), context: context(phones: Set(ids))
        )
        XCTAssertEqual(groups.first?.takeIDs, ids)
    }

    func testSubjectRecursAcrossMomentsByEmbedding() {
        let ids = (0..<4).map { _ in UUID() }
        let assets = [
            asset(ids[0], offset: 0),
            asset(ids[1], offset: 3600),
            asset(ids[2], offset: 7200),
            asset(ids[3], offset: 10800),
        ]
        let chapters = ShootChapterArrangement.arrange(assets)
        XCTAssertEqual(chapters.count, 4)
        var measurements = ElasticInferredGroups.Measurements()
        let look: [Float] = [1, 0, 0]
        let other: [Float] = [0, 1, 0]
        measurements.embeddings = [ids[0]: look, ids[1]: look, ids[2]: other, ids[3]: look]
        measurements.sharpness = [ids[0]: 0.9, ids[1]: 0.5, ids[2]: 0.9, ids[3]: 0.85]

        let groups = ElasticInferredGroups.infer(
            chapters: chapters, assets: assets,
            measurements: measurements, context: context()
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].kind, .sameSubject)
        XCTAssertEqual(groups[0].frameIDs, [ids[0], ids[1], ids[3]])
        XCTAssertEqual(groups[0].takeIDs, [ids[0], ids[3]], "within 85% of the sharpest")
        XCTAssertEqual(groups[0].reason, "3 frames across 3 moments · one look recurs")
        XCTAssertEqual(groups[0].pick, "the sharp ones")
    }

    func testTakingTheLeaderDoesNotMoveTheGroups() {
        // Live bug: the subject representative followed `preferredCoverID`, so marking
        // a burst leader kept swapped in an unmeasured frame and a group vanished.
        let ids = (0..<5).map { _ in UUID() }
        var assets = [
            asset(ids[0], offset: 0), asset(ids[1], offset: 0.4),
            asset(ids[2], offset: 3600), asset(ids[3], offset: 3600.4),
            asset(ids[4], offset: 7200),
        ]
        let chapters = ShootChapterArrangement.arrange(assets)
        var measurements = ElasticInferredGroups.Measurements()
        measurements.embeddings = [ids[0]: [1, 0], ids[2]: [1, 0], ids[4]: [1, 0]]
        measurements.sharpness = [ids[0]: 0.9, ids[1]: 0.2, ids[2]: 0.9, ids[3]: 0.2, ids[4]: 0.9]
        let before = ElasticInferredGroups.infer(chapters: chapters, assets: assets, measurements: measurements, context: context())
        XCTAssertEqual(before.map(\.kind), [.sameBurst, .sameBurst, .sameSubject])

        for id in before.flatMap(\.takeIDs) {
            if let index = assets.firstIndex(where: { $0.id == id }) { assets[index].cull = .keep }
        }
        let after = ElasticInferredGroups.infer(chapters: chapters, assets: assets, measurements: measurements, context: context())
        XCTAssertEqual(after, before, "a mark is not a reason to regroup")
    }

    func testSubjectGroupNeedsTwoMoments() {
        let ids = (0..<2).map { _ in UUID() }
        let assets = [asset(ids[0], offset: 0), asset(ids[1], offset: 30)]
        var measurements = ElasticInferredGroups.Measurements()
        measurements.embeddings = [ids[0]: [1, 0], ids[1]: [1, 0]]
        let groups = ElasticInferredGroups.infer(
            chapters: ShootChapterArrangement.arrange(assets), assets: assets,
            measurements: measurements, context: context()
        )
        XCTAssertEqual(groups.map(\.kind), [.sameScene], "one moment is a scene, not a subject")
    }

    // MARK: - Flags

    func testFlagsNameSoftClipsAndDrift() {
        let id = UUID()
        var frame = asset(id, offset: 0)
        var mate = asset(UUID(), offset: 0.3)
        var third = asset(UUID(), offset: 0.6)
        XCTAssertNil(ElasticInferredGroups.flags(for: frame, burstMates: [frame], measurements: .init()))

        var measurements = ElasticInferredGroups.Measurements()
        measurements.sharpness[id] = 0.1
        XCTAssertEqual(ElasticInferredGroups.flags(for: frame, burstMates: [frame], measurements: measurements), "soft")

        frame.imageStats = ImageStats(highlightClipFraction: 0.05)
        XCTAssertEqual(ElasticInferredGroups.flags(for: frame, burstMates: [frame], measurements: measurements), "soft · clips")

        frame.recipe = EditRecipe(exposure: 1.0)
        mate.recipe = EditRecipe(exposure: 0)
        third.recipe = EditRecipe(exposure: 0.1)
        XCTAssertEqual(
            ElasticInferredGroups.flags(for: frame, burstMates: [frame, mate, third], measurements: measurements),
            "soft · clips · drift"
        )
        measurements.sharpness[id] = 0.8
        XCTAssertEqual(
            ElasticInferredGroups.flags(for: frame, burstMates: [frame, mate, third], measurements: measurements),
            "clips · drift"
        )
    }

    // MARK: - G

    private func seeded() -> (P0SessionModel, [UUID]) {
        let ids = (0..<6).map { _ in UUID() }
        let session = P0SessionModel()
        session.assets = [
            asset(ids[0], offset: 0),
            asset(ids[1], offset: 0.4),
            asset(ids[2], offset: 0.8),
            asset(ids[3], offset: 40),
            asset(ids[4], offset: 60, cull: .reject),
            asset(ids[5], offset: 80, cull: .keep),
        ]
        session.route = .time
        session.focusedAssetID = ids[0]
        session.reconcileActiveChapter()
        return (session, ids)
    }

    func testGTakesThePicksAsOneUndoStep() {
        let (session, ids) = seeded()
        session.inferredMeasurements.sharpness = [ids[0]: 0.3, ids[1]: 0.9, ids[2]: 0.4]
        session.openPeek(.flags)
        XCTAssertEqual(session.peek, .flags)
        let groups = session.inferredGroups
        XCTAssertEqual(groups.map(\.kind), [.sameBurst, .sameScene])
        XCTAssertEqual(groups[0].takeIDs, [ids[1]])
        XCTAssertEqual(Set(groups[1].takeIDs), Set([ids[3], ids[4], ids[5]]))
        XCTAssertEqual(session.inferredPickCount, 2, "the rejected and the kept frame are not picks")
        XCTAssertEqual(session.groupsHeadline, "2 groups inferred")
        XCTAssertEqual(session.groupsSubtitle, "2 picks would go to the set · 0 frames need a hand (soft · clips · drift)")

        let taken = session.takeInferredPicks()
        XCTAssertEqual(taken, 2)
        XCTAssertEqual(session.finalSetAssetIDs, [ids[1], ids[3], ids[5]], "shoot order, the old keep untouched")
        XCTAssertEqual(session.asset(ids[4])?.cull, .reject, "a reject is never overruled")
        XCTAssertEqual(session.peek, .flags, "G leaves the peek where it was")
        XCTAssertEqual(session.undoCoordinator.undoLabel, "Undo Take the picks")

        session.undoLast()
        XCTAssertEqual(session.finalSetAssetIDs, [ids[5]], "one ⌘Z puts every pick back")
        XCTAssertEqual(session.asset(ids[1])?.cull, .undecided)
        XCTAssertEqual(session.takeInferredPicks(), 2, "and G can take them again")
    }

    func testGWithNothingToTakeIsANoOp() {
        let (session, ids) = seeded()
        for id in ids where session.asset(id)?.cull == .undecided {
            if let index = session.assets.firstIndex(where: { $0.id == id }) {
                session.assets[index].cull = .keep
            }
        }
        session.openPeek(.flags)
        XCTAssertEqual(session.takeInferredPicks(), 0)
        XCTAssertNil(session.undoCoordinator.undoLabel)
    }

    func testFlagsOnlyShowWhileFlagsAreHeld() {
        let (session, ids) = seeded()
        session.inferredMeasurements.sharpness = [ids[0]: 0.05]
        XCTAssertNil(session.flagLine(for: ids[0]))
        session.openPeek(.flags)
        XCTAssertEqual(session.flagLine(for: ids[0]), "soft")
        XCTAssertEqual(session.flaggedFrameCount, 1)
        session.closePeek()
        XCTAssertNil(session.flagLine(for: ids[0]))
    }

    func testGroupsLayoutMatchesTheDesign() {
        XCTAssertEqual(ElasticLayout.groupsColumnWidth, 210)
        XCTAssertEqual(ElasticLayout.groupsFrame, CGSize(width: 96, height: 64))
        XCTAssertEqual(ElasticLayout.groupsMaxHeight, 304, "38vh at the minimum window")
        XCTAssertEqual(ElasticLayout.groupsFocusRowOpacity, 0.14, accuracy: 1e-9)
        XCTAssertEqual(ElasticLayout.groupsRowOpacity, 0.22, accuracy: 1e-9)
        XCTAssertEqual(ElasticLayout.groupsUntakenOpacity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(ElasticLayout.bornGroupsMs, 240)
    }
}
