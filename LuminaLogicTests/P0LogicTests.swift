import XCTest
@testable import Lumina

/// Native XCTest logic tests for P0 state / command logic. These complement — and do not replace —
/// the repository's existing standalone `Scripts/*.swift` deterministic tests; they exercise the
/// same contracts from inside the module and additionally guard the accessibility-identifier and
/// state-probe contracts the UI harness depends on.
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
}
