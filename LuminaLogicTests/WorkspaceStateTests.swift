import XCTest
@testable import Lumina

final class WorkspaceStateTests: XCTestCase {
    func testFocusSelectionAndTemporaryExpansionAreIndependent() {
        let focus = UUID()
        let second = UUID()
        let third = UUID()
        let related = [UUID(), UUID()]
        var state = WorkspaceState()

        state.focus(focus)
        state.select([second, third])
        state.expandTemporarily(related)

        XCTAssertEqual(state.focusedAssetID, focus)
        XCTAssertEqual(state.selectedAssetIDs, [second, third])
        XCTAssertEqual(state.temporarilyExpandedAssetIDs, related)

        state.releaseTemporaryExpansion()

        XCTAssertEqual(state.focusedAssetID, focus)
        XCTAssertEqual(state.selectedAssetIDs, [second, third])
        XCTAssertTrue(state.temporarilyExpandedAssetIDs.isEmpty)
    }

    func testSelectionKeepsInsertionOrderAndDoesNotDuplicateAssets() {
        let first = UUID()
        let second = UUID()
        var state = WorkspaceState()

        state.select([second, first, second])
        state.toggleSelection(first)
        state.toggleSelection(first)

        XCTAssertEqual(state.selectedAssetIDs, [second, first])
    }

    func testComparisonAndScopeDoNotMutateFocusOrSelection() {
        let focus = UUID()
        let selected = UUID()
        let comparisons = [UUID(), UUID()]
        var state = WorkspaceState(
            focusedAssetID: focus,
            selectedAssetIDs: [selected]
        )

        state.compare(comparisons)
        state.setScope(.scene)

        XCTAssertEqual(state.comparisonAssetIDs, comparisons)
        XCTAssertEqual(state.currentScope, .scene)
        XCTAssertEqual(state.focusedAssetID, focus)
        XCTAssertEqual(state.selectedAssetIDs, [selected])
    }

    func testClearWorkspaceRemovesAllTemporaryState() {
        var state = WorkspaceState(
            focusedAssetID: UUID(),
            selectedAssetIDs: [UUID()],
            temporarilyExpandedAssetIDs: [UUID()],
            comparisonAssetIDs: [UUID()],
            currentScope: .shoot
        )

        state.clear()

        XCTAssertNil(state.focusedAssetID)
        XCTAssertTrue(state.selectedAssetIDs.isEmpty)
        XCTAssertTrue(state.temporarilyExpandedAssetIDs.isEmpty)
        XCTAssertTrue(state.comparisonAssetIDs.isEmpty)
        XCTAssertEqual(state.currentScope, .row)
    }

    func testReopenRestoresFocusWithoutPersistingTemporaryExpansion() {
        let focus = UUID()
        let expanded = UUID()
        var original = WorkspaceState(focusedAssetID: focus)
        original.expandTemporarily([expanded])

        let durable = WorkspaceRestoreState(focusedAssetID: original.focusedAssetID)
        var reopened = WorkspaceState(
            selectedAssetIDs: [expanded],
            temporarilyExpandedAssetIDs: [expanded],
            comparisonAssetIDs: [focus, expanded],
            currentScope: .shoot
        )
        reopened.restore(from: durable, availableAssetIDs: [focus, expanded])

        XCTAssertEqual(reopened.focusedAssetID, focus)
        XCTAssertTrue(reopened.selectedAssetIDs.isEmpty)
        XCTAssertTrue(reopened.temporarilyExpandedAssetIDs.isEmpty)
        XCTAssertTrue(reopened.comparisonAssetIDs.isEmpty)
        XCTAssertEqual(reopened.currentScope, .row)
    }

    func testTemporaryWorkspaceStateCannotEnterCanonicalPersistence() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let canonical = try String(
            contentsOf: root.appendingPathComponent("Lumina/Models/P0State.swift"),
            encoding: .utf8
        )
        let workspace = try String(
            contentsOf: root.appendingPathComponent("Lumina/ViewModels/WorkspaceState.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(canonical.contains("temporarilyExpandedAssetIDs"))
        XCTAssertFalse(canonical.contains("comparisonAssetIDs"))
        XCTAssertFalse(workspace.contains(": Codable"))
    }
}
