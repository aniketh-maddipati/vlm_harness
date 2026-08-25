import XCTest
@testable import Lumina

/// Native XCTest logic tests for P0 state / command logic — real types via `@testable import Lumina`.
@MainActor
final class P0LogicTests: XCTestCase {

    // MARK: - Cull toggle grammar (same contract the UI cull flow drives)

    func testCullToggleGrammar() {
        XCTAssertEqual(CullMutationCommand.resolveToggle(current: .undecided, pressed: .keep), .keep)
        XCTAssertEqual(CullMutationCommand.resolveToggle(current: .keep, pressed: .keep), .undecided)
        XCTAssertEqual(CullMutationCommand.resolveToggle(current: .undecided, pressed: .reject), .reject)
        XCTAssertEqual(CullMutationCommand.resolveToggle(current: .reject, pressed: .reject), .undecided)
        // Direct switch keep -> reject and reject -> keep (no clear).
        XCTAssertEqual(CullMutationCommand.resolveToggle(current: .keep, pressed: .reject), .reject)
        XCTAssertEqual(CullMutationCommand.resolveToggle(current: .reject, pressed: .keep), .keep)
    }

    // MARK: - Undo coordinator

    func testUndoCoordinatorStack() {
        let coordinator = P0UndoCoordinator()
        XCTAssertFalse(coordinator.canUndo)
        let cmd = CullMutationCommand(
            assetID: UUID(), before: .undecided, after: .keep,
            finalOrderBefore: [], finalOrderAfter: []
        )
        coordinator.push(cmd)
        XCTAssertTrue(coordinator.canUndo)
        XCTAssertEqual(coordinator.popCull(), cmd)
        XCTAssertFalse(coordinator.canUndo)
    }

    // MARK: - Final-set membership reconciliation

    func testKeptMembershipReconciliation() {
        let a = UUID(), b = UUID(), c = UUID()
        var order = FinalSetOrder(assetIDs: [a, b])
        order.reconcileKeptMembership(keptIDsInChronologicalOrder: [b, c])
        XCTAssertFalse(order.assetIDs.contains(a), "dropped keep removed from custom order")
        XCTAssertTrue(order.assetIDs.contains(c), "new keep appended to custom order")
    }

    // MARK: - Accessibility-identifier contract (app side of the mirror)

    func testAccessibilityIdentifierContract() {
        XCTAssertEqual(P0AccessibilityID.contactSheet, "p0.contactSheet")
        XCTAssertEqual(P0AccessibilityID.selectionCount, "p0.selectionCount")
        XCTAssertEqual(P0AccessibilityID.stateProbe, "p0.stateProbe")
        let id = UUID()
        XCTAssertEqual(P0AccessibilityID.assetCell(id), "p0.asset.\(id.uuidString)")
        XCTAssertEqual(P0AccessibilityID.filmstripItem(id), "p0.filmstrip.\(id.uuidString)")
        XCTAssertEqual(P0AccessibilityID.chapterMark("abc"), "p0.chapter.abc")
        XCTAssertEqual(P0AccessibilityID.keptRail, "p0.keptRail")
    }

    // MARK: - State-probe JSON round trip (schema the harness decodes)

    func testProbeSnapshotRoundTrips() {
        let snapshot = ProbeSnapshot(
            route: "contactSheet", shootName: "mixed-60", fixture: "mixed-60", seed: "84721",
            assetCount: 60, visibleCount: 60, selectionCount: 2, keptCount: 18, rejectedCount: 9,
            unreviewedCount: 33, editedCount: 12, densityColumns: 6, filter: "All", canUndo: true,
            focusedAssetID: "abc", focusedVisible: true, focusedAvailability: "available",
            focusedCull: "keep", focusedRecipeFingerprint: "fp-abc", pointerCullTargetsVisible: true, inspectingAssetID: nil, selectedAssetIDs: ["a", "b"],
            missingOriginalCount: 0, previewReadyCount: 60, phaseDetail: "60 photos",
            scrollAnchor: 0, culls: ["a": "keep"], editedIDs: ["a"], visibleAssetIDs: ["a", "b"],
            missingAssetIDs: [], reduceMotionActive: false, keyRoutingOwner: "P0KeyRoutingModifier", legacyShellActive: false,
                renderInstrumentsEnabled: false
        )
        let json = snapshot.jsonString()
        let decoded = try? JSONDecoder().decode(ProbeSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, snapshot)
    }

    // MARK: - A1 staged-copy invariant (banner, header, receipt share ONE count)

    func testA1InvariantRowScope() {
        let snapshot = StagingCopySnapshot(
            scopeCount: 4,
            rowIndex: 4,
            laneTimestamp: "18:17"
        )
        let header = CopyContract.stagedHeader(snapshot)
        let banner = CopyContract.adaptBanner(snapshot)
        let receipt = CopyContract.adaptedReceipt(count: snapshot.scopeCount)
        XCTAssertTrue(A1Invariant.validate(header: header, banner: banner, receipt: receipt, snapshot: snapshot))
    }

    func testA1FormatterSamplesInCopyContract() throws {
        let contractURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("design/copy-contract.txt")
        let contract = try String(contentsOf: contractURL, encoding: .utf8)
        let samples = [
            CopyContract.stagedHeader(StagingCopySnapshot(scopeCount: 4, rowIndex: 4, laneTimestamp: "18:17")),
            CopyContract.adaptBanner(StagingCopySnapshot(scopeCount: 4)),
            CopyContract.adaptedReceipt(count: 4),
            CopyContract.stagedHeader(StagingCopySnapshot(
                scopeCount: 12, excludedCount: 2, rowIndex: 4, laneTimestamp: "18:17", ring: .scene
            )),
            CopyContract.adaptBanner(StagingCopySnapshot(scopeCount: 12, excludedCount: 2, ring: .shoot)),
        ]
        for sample in samples {
            XCTAssertTrue(contract.contains(sample), "Formatted copy missing from contract: \(sample)")
        }
    }

    func testA1InvariantExcludedCount() {
        let snapshot = StagingCopySnapshot(
            scopeCount: 12,
            excludedCount: 2,
            rowIndex: 4,
            laneTimestamp: "18:17",
            ring: .scene
        )
        let header = CopyContract.stagedHeader(snapshot)
        let banner = CopyContract.adaptBanner(
            StagingCopySnapshot(
                scopeCount: 12,
                excludedCount: 2,
                rowIndex: 4,
                laneTimestamp: "18:17",
                ring: .shoot
            )
        )
        let receipt = CopyContract.adaptedReceipt(count: snapshot.scopeCount)
        XCTAssertTrue(A1Invariant.validate(header: header, banner: banner, receipt: receipt, snapshot: snapshot))
    }

    // MARK: - Table layout (swim lanes, wrap-shares-lane, geometry)

    func testSwimLaneWrapSharesLane() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = start.addingTimeInterval(8 * 60)
        let part1 = GroupPresentation(
            id: "p1",
            title: "Set 1",
            assets: [],
            timeStart: start,
            timeEnd: end,
            siblingGroupID: "lane-a",
            siblingPartIndex: 1,
            siblingPartCount: 2
        )
        let part2 = GroupPresentation(
            id: "p2",
            title: "Set 1 continued",
            assets: [],
            timeStart: end.addingTimeInterval(60),
            timeEnd: end.addingTimeInterval(9 * 60),
            siblingGroupID: "lane-a",
            siblingPartIndex: 2,
            siblingPartCount: 2
        )
        let units = TableLayout.swimLaneUnits(from: [part1, part2])
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].groups.count, 2)
        XCTAssertEqual(units[0].laneHeader, CopyContractBuilder.laneTimestamp(from: start))
        XCTAssertTrue(TableLayout.wrapSharesLane(part2))
    }

    func testTableLayoutGeometry() {
        XCTAssertEqual(TableLayout.responsivePageSize(twoUp: true, availableWidth: 1400), 2)
        XCTAssertGreaterThanOrEqual(TableLayout.compactVisibleCount(availableWidth: 900), 4)
        let width = TableLayout.comparisonTileWidth(availableWidth: 1100, pageSize: 4, twoUp: false)
        XCTAssertGreaterThanOrEqual(width, 280)
        XCTAssertLessThanOrEqual(width, 720)
        let compression = TableLayout.comparisonCompression(pageSize: 4, hasSelection: true)
        XCTAssertGreaterThan(compression.focusScale, compression.neighborScale)
    }

    // MARK: - Crop latch (frame C)

    func testCropLayoutHashRestoration() {
        let recipe = EditRecipe(
            crop: EditCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.6),
            straightenDegrees: 1.0
        )
        var session = CropSession(photoID: UUID(), recipe: recipe)
        let baselineHash = session.baseline.layoutHash
        session.working.photoPanX = 0.4
        session.working.straightenDegrees = 4.2
        session.flipOrientation()
        XCTAssertNotEqual(session.working.layoutHash, baselineHash)
        session.revert()
        XCTAssertEqual(session.working.layoutHash, baselineHash)
    }

    func testCropStraightenMagnet() {
        var session = CropSession(photoID: UUID(), recipe: .neutral)
        session.setStraighten(0.3)
        XCTAssertEqual(session.working.straightenDegrees, 0, accuracy: 0.01)
        session.setStraighten(2.5)
        XCTAssertEqual(session.working.straightenDegrees, 2.5, accuracy: 0.01)
    }

    func testCropKeyScopeNeverStagesOrRejects() {
        // Crop latch re-scoping (.cursorrules frame C).
        XCTAssertNotEqual(CropSessionCopy.header(straightenDegrees: 0).contains("reject"), true)
        var session = CropSession(photoID: UUID(), recipe: .neutral)
        session.toggleAspectLock()
        XCTAssertTrue(session.working.aspectUnlocked)
        session.flipOrientation()
        XCTAssertTrue(session.working.orientationFlipped)
    }

    // MARK: - Develop staging (H4)

    func testDevelopStagingActionIsDevelopFlag() {
        let id = UUID()
        let action = StagedAction.develop(proposals: [id: .neutral])
        XCTAssertTrue(action.isDevelopStaging)
        XCTAssertFalse(StagedAction.treat(.neutral).isDevelopStaging)
    }

    func testDevelopBannerA1ScopeCount() {
        let snapshot = StagingCopySnapshot(scopeCount: 1, isDevelop: true)
        let header = CopyContract.stagedHeader(snapshot)
        let banner = CopyContract.developBanner(count: snapshot.scopeCount)
        XCTAssertTrue(A1Invariant.validate(header: header, banner: banner, receipt: banner, snapshot: snapshot))
    }

    func testDevelopAdjustmentsFromProposal() {
        var base = DevelopRecipe.neutral
        base.exposure = 0.2
        base.temperature = 6000
        base.contrast = 10
        var proposal = EditRecipe.neutral
        proposal.exposure = 0.5
        proposal.temperature = 5500
        proposal.contrast = 20
        let offsets = DevelopAdjustments.from(proposal: proposal, base: base)
        XCTAssertEqual(offsets.exposure, 0.3, accuracy: 0.001)
        XCTAssertEqual(offsets.temperature, -500, accuracy: 0.001)
        XCTAssertEqual(offsets.contrast, 10, accuracy: 0.001)
    }

    // MARK: - Table hand selection (H5)

    func testTablePhotographSelectionCrossRow() {
        let a = UUID(), b = UUID(), c = UUID()
        var sel = TablePhotographSelection()
        sel.rubberBand([a, c])
        XCTAssertEqual(sel.count, 2)
        sel.extend(in: [a, b, c], to: b)
        XCTAssertTrue(sel.set.contains(b))
        XCTAssertEqual(sel.count, 3)
    }

    func testDevelopBannerCrossRowCount() {
        let snapshot = StagingCopySnapshot(scopeCount: 4, isDevelop: true)
        let banner = CopyContract.developBanner(count: snapshot.scopeCount)
        XCTAssertTrue(A1Invariant.validate(
            header: CopyContract.stagedHeader(snapshot),
            banner: banner,
            receipt: banner,
            snapshot: snapshot
        ))
    }

    func testDevelopCommitCapturesPriorEditForUndo() throws {
        let photoID = UUID()
        let prior = EditRecipe.neutral
        var priorMutated = prior
        priorMutated.exposure = 0.4
        let entry = DecisionLedgerEntry(
            photoID: photoID,
            priorTier: .unranked,
            priorFlagged: false,
            priorUncertaintyKind: .none,
            priorWhyUncertain: nil,
            applied: .undecided,
            priorEditRecipe: priorMutated
        )
        XCTAssertEqual(try XCTUnwrap(entry.priorEditRecipe?.exposure), 0.4, accuracy: 0.001)
    }

    // MARK: - Wholesale propagation (H6)

    func testPropagationRingWidenNarrowOrder() {
        var state = PropagationState(
            referencePhotoID: UUID(),
            referenceGroupID: "g1",
            referenceFrame: "8288"
        )
        XCTAssertEqual(state.ring, .row)
        XCTAssertTrue(state.widen())
        XCTAssertEqual(state.ring, .scene)
        XCTAssertTrue(state.widen())
        XCTAssertEqual(state.ring, .shoot)
        XCTAssertFalse(state.widen())
        XCTAssertTrue(state.narrow())
        XCTAssertEqual(state.ring, .scene)
        XCTAssertTrue(state.narrow())
        XCTAssertEqual(state.ring, .row)
        XCTAssertFalse(state.narrow())
    }

    func testA1InvariantShootExcluded() {
        let snapshot = StagingCopySnapshot(
            scopeCount: 12,
            excludedCount: 2,
            rowIndex: 4,
            ring: .shoot
        )
        let header = CopyContract.stagedHeader(snapshot)
        let banner = CopyContract.adaptBanner(snapshot)
        let receipt = CopyContract.adaptedReceipt(count: snapshot.scopeCount)
        XCTAssertTrue(A1Invariant.validate(header: header, banner: banner, receipt: receipt, snapshot: snapshot))
    }

    // MARK: - Edit rail layout (frame 12 / hi-fi H7)

    func testHistogramContractSize() {
        XCTAssertEqual(HiFiTokens.Histogram.width, 252)
        XCTAssertEqual(HiFiTokens.Histogram.height, 64)
    }

    func testEditRailLayoutMinWindow() {
        XCTAssertEqual(EditRailLayout.minWindowWidth, 1280)
        XCTAssertEqual(EditRailLayout.minWindowHeight, 800)
        XCTAssertTrue(EditRailLayout.isCompact(windowHeight: 800))
        XCTAssertFalse(EditRailLayout.showsHistogram(windowHeight: 800))
        XCTAssertEqual(EditRailLayout.targetsHeight, 460)
        XCTAssertEqual(EditRailLayout.rowCount, 10)
        XCTAssertEqual(EditRailLayout.rowHeight, 46)
        XCTAssertTrue(EditRailLayout.straightenRowFits(windowHeight: 800, contextVisible: false))
        // Histogram yields only at the min window; it returns as soon as there is headroom
        // (h7 oracle 753b9df: "histogram should show above min window height").
        XCTAssertTrue(EditRailLayout.showsHistogram(windowHeight: 801))
    }

    func testExportRecipeHintContract() {
        XCTAssertEqual(CopyContract.exportRecipeHint, "⌥⌘E changes the recipe.")
    }

    // MARK: - W5 Esc ladder (single owner)

    func testEscLadderLeavesGrouping() {
        let session = P0SessionModel()
        session.route = .grouping
        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertEqual(session.route, .contactSheet)
    }

    func testEscLadderClosesInspectionWithoutChangingRoute() {
        let session = P0SessionModel()
        session.route = .contactSheet
        let id = UUID()
        session.inspectingAssetID = id
        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertNil(session.inspectingAssetID)
        XCTAssertEqual(session.route, .contactSheet)
    }

    func testEscLadderNoOpOnBareContactSheet() {
        let session = P0SessionModel()
        session.route = .contactSheet
        XCTAssertFalse(P0EscLadder.handle(session: session))
    }

    func testEscLadderEndsLookGlanceBeforeGrouping() {
        let session = P0SessionModel()
        session.route = .contactSheet
        session.lookGlancing = true
        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertFalse(session.lookGlancing)
        XCTAssertEqual(session.route, .contactSheet)
    }

    // MARK: - Open-surface shoot ranking

    func testOpenShootArrangementResumeAndImpact() {
        let now = Date()
        let tiny = RecentShootSummary(
            id: UUID(), name: "scratch", assetCount: 6, keepCount: 0,
            lastOpenedAt: now, rawFolderPath: nil
        )
        let wedding = RecentShootSummary(
            id: UUID(), name: "wedding", assetCount: 420, keepCount: 18,
            lastOpenedAt: now.addingTimeInterval(-3600), rawFolderPath: nil
        )
        let portraits = RecentShootSummary(
            id: UUID(), name: "portraits", assetCount: 180, keepCount: 4,
            lastOpenedAt: now.addingTimeInterval(-7200), rawFolderPath: nil
        )
        let arranged = OpenShootArrangement.arrange([tiny, wedding, portraits])
        XCTAssertEqual(arranged.resume?.name, "scratch")
        XCTAssertEqual(arranged.largerSets.map(\.name), ["wedding", "portraits"])
        XCTAssertTrue(arranged.smaller.isEmpty)
    }

    func testOpenShootArrangementAllSmallStaySmall() {
        let now = Date()
        let first = RecentShootSummary(
            id: UUID(), name: "a", assetCount: 4, keepCount: 0,
            lastOpenedAt: now, rawFolderPath: nil
        )
        let second = RecentShootSummary(
            id: UUID(), name: "b", assetCount: 8, keepCount: 0,
            lastOpenedAt: now.addingTimeInterval(-10), rawFolderPath: nil
        )
        let arranged = OpenShootArrangement.arrange([first, second])
        XCTAssertEqual(arranged.resume?.name, "a")
        XCTAssertTrue(arranged.largerSets.isEmpty)
        XCTAssertEqual(arranged.smaller.map(\.name), ["b"])
    }

    func testOpenShootArrangementEmpty() {
        let arranged = OpenShootArrangement.arrange([])
        XCTAssertNil(arranged.resume)
        XCTAssertTrue(arranged.largerSets.isEmpty)
        XCTAssertTrue(arranged.smaller.isEmpty)
    }

    // MARK: - Chapter table (time rail)

    private func datedAsset(id: UUID, offset: TimeInterval, cull: CullDecision = .undecided) -> AssetRecord {
        AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: "/x/\(id.uuidString).ARW",
                relativePath: "\(id.uuidString).ARW",
                volumeID: "VOL",
                availability: .available
            ),
            filename: "asset-\(id.uuidString).ARW",
            cull: cull,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset)
        )
    }

    func testChapterArrangementTightSpacingIsOneChapter() {
        let assets = (0..<60).map { index in
            datedAsset(id: UUID(), offset: Double(index) * 3)
        }
        let chapters = ShootChapterArrangement.arrange(assets)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].assetIDs.count, 60)
        XCTAssertEqual(chapters[0].bursts.count, 60, "3s gaps stay singleton bursts")
    }

    func testChapterArrangementSplitsOnLongPause() {
        let early = (0..<8).map { index in
            datedAsset(id: UUID(), offset: Double(index) * 3)
        }
        let late = (0..<5).map { index in
            datedAsset(id: UUID(), offset: 20 * 60 + Double(index) * 3)
        }
        let chapters = ShootChapterArrangement.arrange(early + late)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].assetIDs.count, 8)
        XCTAssertEqual(chapters[1].assetIDs.count, 5)
    }

    func testBurstArrangementMergesSubTwoSecondFrames() {
        let ids = (0..<5).map { _ in UUID() }
        let assets = ids.enumerated().map { index, id in
            datedAsset(id: id, offset: Double(index) * 0.4)
        }
        let bursts = ShootChapterArrangement.bursts(in: assets)
        XCTAssertEqual(bursts.count, 1)
        XCTAssertEqual(bursts[0].assetIDs, ids)
        XCTAssertEqual(bursts[0].frameCount, 5)
    }

    func testCaptureNamePairsRawAndJpegAndStripsVersionSuffix() {
        let raw = CaptureName.parse("IMG_2841.CR3")
        let jpeg = CaptureName.parse("IMG_2841.JPG")
        let extra = CaptureName.parse("IMG_2841_1.JPG")
        XCTAssertEqual(raw.stemKey, jpeg.stemKey)
        XCTAssertEqual(raw.stemKey, extra.stemKey)
        XCTAssertEqual(raw.sequence, 2841)
        XCTAssertEqual(CaptureName.parse("DSC02841.ARW").sequence, 2841)
    }

    func testStemCollapsePairsSiblingsIntoOneFrame() {
        let raw = UUID()
        let jpeg = UUID()
        let assets = [
            namedAsset(id: raw, filename: "IMG_2841.CR3", offset: 0),
            namedAsset(id: jpeg, filename: "IMG_2841.JPG", offset: 0, thumbPath: "/tmp/2841.jpg"),
        ]
        let frames = ShootChapterArrangement.collapseStems(assets)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(Set(frames[0].assetIDs), Set([raw, jpeg]))
        XCTAssertEqual(frames[0].coverID, jpeg, "previewed sibling is the cover")
        XCTAssertEqual(ShootChapterArrangement.bursts(from: frames).count, 1)
        XCTAssertEqual(ShootChapterArrangement.bursts(from: frames)[0].frameCount, 1)
    }

    func testNamedRunWithoutDatesCollapsesConsecutiveStems() {
        let first = UUID()
        let second = UUID()
        let assets = [
            namedAsset(id: first, filename: "IMG_2841.ARW", offset: nil),
            namedAsset(id: second, filename: "IMG_2842.ARW", offset: nil),
        ]
        let bursts = ShootChapterArrangement.bursts(in: assets)
        XCTAssertEqual(bursts.count, 1)
        XCTAssertEqual(bursts[0].frameCount, 2)
        XCTAssertEqual(bursts[0].assetIDs, [first, second])
    }

    func testConsecutiveNamesThreeSecondsApartStaySeparateBursts() {
        let first = UUID()
        let second = UUID()
        let assets = [
            namedAsset(id: first, filename: "IMG_0001.JPG", offset: 0),
            namedAsset(id: second, filename: "IMG_0002.JPG", offset: 3),
        ]
        let bursts = ShootChapterArrangement.bursts(in: assets)
        XCTAssertEqual(bursts.count, 2, "time must confirm a named run; 3s fixture stays readable")
    }

    private func namedAsset(
        id: UUID,
        filename: String,
        offset: TimeInterval?,
        thumbPath: String? = nil
    ) -> AssetRecord {
        AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: "/x/\(filename)",
                relativePath: filename,
                volumeID: "VOL",
                availability: .available
            ),
            filename: filename,
            capturedAt: offset.map { Date(timeIntervalSince1970: 1_700_000_000 + $0) },
            thumbPath: thumbPath
        )
    }

    func testChapterBoardFiltersVisibleItemsAndArrowWalksBursts() {
        let first = UUID()
        let second = UUID()
        let later = UUID()
        let session = P0SessionModel()
        session.assets = [
            datedAsset(id: first, offset: 0),
            datedAsset(id: second, offset: 3),
            datedAsset(id: later, offset: 46 * 60),
        ]
        session.focusedAssetID = first
        session.reconcileActiveChapter()
        XCTAssertEqual(session.chapters.count, 2)
        XCTAssertEqual(session.visibleItems.map(\.id), [first, second])

        session.moveFocus(dx: 1, dy: 0, columns: 6)
        XCTAssertEqual(session.focusedAssetID, second)

        session.moveFocus(dx: 0, dy: 1, columns: 6)
        XCTAssertEqual(session.activeChapterID, session.chapters[1].id)
        XCTAssertEqual(session.focusedAssetID, later)
        XCTAssertEqual(session.visibleItems.map(\.id), [later])
    }

    func testChapterArrangementWalkPauseSplitsWhenMedianIsLarge() {
        let assets = [0.0, 5 * 60, 10 * 60, 20 * 60].map { datedAsset(id: UUID(), offset: $0) }
        let chapters = ShootChapterArrangement.arrange(assets)
        XCTAssertEqual(chapters.count, 2, "10 min walk splits when the median gap is already minutes")
        XCTAssertEqual(chapters[0].assetIDs.count, 3)
        XCTAssertEqual(chapters[1].assetIDs.count, 1)
    }

    func testRodGapsGrowWithElapsedTime() {
        let assets = [0.0, 10 * 60, 50 * 60].map { datedAsset(id: UUID(), offset: $0) }
        let chapters = ShootChapterArrangement.arrange(assets)
        XCTAssertEqual(chapters.count, 3)
        let gaps = ChapterRodLayout.gaps(between: chapters)
        XCTAssertEqual(gaps.count, 2)
        XCTAssertGreaterThan(gaps[1], gaps[0])
        XCTAssertNotNil(ChapterRodLayout.elapsedLabel(seconds: 10 * 60))
        XCTAssertNil(ChapterRodLayout.elapsedLabel(seconds: 90))
    }

    func testChapterPackPrefersReadablePlatesUntilLeaned() {
        let rest = ChapterPack.columns(count: 3, width: 900, height: 700, leanedColumns: nil)
        XCTAssertLessThanOrEqual(rest.columns, 3)
        XCTAssertGreaterThanOrEqual(rest.plateHeight, ChapterPack.readable)

        let leaned = ChapterPack.columns(count: 40, width: 900, height: 700, leanedColumns: 8)
        XCTAssertEqual(leaned.columns, 8)
        XCTAssertLessThan(leaned.plateHeight, ChapterPack.readable)
    }

    func testKeepFocusedBurstRejectsRestAndOneUndoRestores() {
        let keeper = UUID()
        let sibling = UUID()
        let later = UUID()
        let session = P0SessionModel()
        session.assets = [
            datedAsset(id: keeper, offset: 0),
            datedAsset(id: sibling, offset: 3),
            datedAsset(id: later, offset: 46 * 60),
        ]
        session.focusedAssetID = keeper
        session.reconcileActiveChapter()
        XCTAssertEqual(session.chapters.count, 2)

        session.keepFocusedBurst()
        XCTAssertEqual(session.assets.first { $0.id == keeper }?.cull, .keep)
        XCTAssertEqual(session.assets.first { $0.id == sibling }?.cull, .reject)
        XCTAssertEqual(session.assets.first { $0.id == later }?.cull, .undecided)
        XCTAssertEqual(session.keptRailAssets.map(\.id), [keeper])
        XCTAssertEqual(session.activeChapterID, session.chapters[1].id)
        XCTAssertEqual(session.undoLabel, "Undo Keep burst")

        session.undoLast()
        XCTAssertEqual(session.assets.first { $0.id == keeper }?.cull, .undecided)
        XCTAssertEqual(session.assets.first { $0.id == sibling }?.cull, .undecided)
        XCTAssertTrue(session.keptRailAssets.isEmpty)
        XCTAssertEqual(session.activeChapterID, session.chapters[0].id)
        XCTAssertEqual(session.focusedAssetID, keeper)
    }

    func testLookGlanceBeginAndEndReturnsToTime() {
        let first = UUID()
        let second = UUID()
        let session = P0SessionModel()
        session.assets = [
            datedAsset(id: first, offset: 0),
            datedAsset(id: second, offset: 3),
        ]
        session.focusedAssetID = first
        session.reconcileActiveChapter()
        session.beginLookGlance()
        XCTAssertTrue(session.lookGlancing)
        XCTAssertEqual(session.glanceBurstIDs.count, 2)
        session.endLookGlance()
        XCTAssertFalse(session.lookGlancing)
        XCTAssertTrue(session.glanceBurstIDs.isEmpty)
    }

    func testLeanIntoBurstThenEscReturnsToChapter() {
        let ids = (0..<4).map { _ in UUID() }
        let session = P0SessionModel()
        session.assets = ids.enumerated().map { index, id in
            datedAsset(id: id, offset: Double(index) * 0.4)
        }
        session.focusedAssetID = ids[0]
        session.reconcileActiveChapter()
        XCTAssertEqual(session.focusedBurst?.frameCount, 4)

        session.activateFocusedPhotograph()
        XCTAssertEqual(session.leanedBurstID, session.focusedBurst?.id)
        XCTAssertNil(session.inspectingAssetID)

        XCTAssertTrue(P0EscLadder.handle(session: session))
        XCTAssertNil(session.leanedBurstID)
        XCTAssertNil(session.inspectingAssetID)
    }

    func testActivateSingletonOpensInspect() {
        let first = UUID()
        let second = UUID()
        let session = P0SessionModel()
        session.assets = [
            datedAsset(id: first, offset: 0),
            datedAsset(id: second, offset: 3),
        ]
        session.focusedAssetID = first
        session.reconcileActiveChapter()
        session.activateFocusedPhotograph()
        XCTAssertEqual(session.inspectingAssetID, first)
        XCTAssertNil(session.leanedBurstID)
    }
}
