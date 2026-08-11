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
    }

    // MARK: - State-probe JSON round trip (schema the harness decodes)

    func testProbeSnapshotRoundTrips() {
        let snapshot = ProbeSnapshot(
            route: "contactSheet", shootName: "mixed-60", fixture: "mixed-60", seed: "84721",
            assetCount: 60, visibleCount: 60, selectionCount: 2, keptCount: 18, rejectedCount: 9,
            unreviewedCount: 33, editedCount: 12, densityColumns: 6, filter: "All", canUndo: true,
            focusedAssetID: "abc", focusedVisible: true, focusedAvailability: "available",
            focusedCull: "keep", inspectingAssetID: nil, selectedAssetIDs: ["a", "b"],
            missingOriginalCount: 0, previewReadyCount: 60, phaseDetail: "60 photos",
            scrollAnchor: 0, culls: ["a": "keep"], editedIDs: ["a"], visibleAssetIDs: ["a", "b"],
            missingAssetIDs: []
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
        XCTAssertFalse(EditRailLayout.showsHistogram(windowHeight: 801))
    }

    func testExportRecipeHintContract() {
        XCTAssertEqual(CopyContract.exportRecipeHint, "⌥⌘E changes the recipe.")
    }
}
