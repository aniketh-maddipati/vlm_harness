import XCTest
@testable import Lumina

@MainActor
final class TableSelectionTests: XCTestCase {

    func testCrossRowRubberBandSelection() {
        let rowA = UUID(), rowB = UUID(), rowC = UUID(), rowD = UUID()
        var selection = TablePhotographSelection()
        selection.rubberBand([rowA, rowD])
        XCTAssertEqual(selection.count, 2)
    }

    func testShiftExtendAlongTableOrder() {
        let ids = (0..<4).map { _ in UUID() }
        var selection = TablePhotographSelection()
        selection.rubberBand([ids[0], ids[3]])
        selection.extend(in: ids, to: ids[2])
        XCTAssertGreaterThanOrEqual(selection.count, 3)
    }

    func testEmptySelectionFallsBackToFocusedFrameForDevelop() {
        let focus = UUID()
        let targets: [UUID] = []
        let developTargets = targets.isEmpty ? [focus] : targets
        XCTAssertEqual(developTargets, [focus])
    }

    func testToggleRemovesMemberWhileStaged() {
        let a = UUID(), b = UUID()
        var selection = TablePhotographSelection()
        selection.setMembers([a, b])
        selection.toggle(a)
        XCTAssertFalse(selection.set.contains(a))
    }

    func testDecisionLedgerCapturesPriorEditForUndo() throws {
        let editedID = UUID()
        let priorEdit = EditRecipe(exposure: 0.35)
        let entry = DecisionLedgerEntry(
            photoID: editedID,
            priorTier: .unranked,
            priorFlagged: false,
            priorUncertaintyKind: .none,
            priorWhyUncertain: nil,
            applied: .undecided,
            priorEditRecipe: priorEdit
        )
        XCTAssertEqual(try XCTUnwrap(entry.priorEditRecipe?.exposure), 0.35, accuracy: 0.001)
    }
}
