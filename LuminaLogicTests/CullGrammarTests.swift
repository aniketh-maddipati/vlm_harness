import XCTest
@testable import Lumina

/// Pure cull grammar — headless event → state (F02.1).
final class CullGrammarTests: XCTestCase {

    private func asset(_ machine: CullGrammarMachine, at index: Int) -> UUID {
        machine.state.assetIDs[index]
    }

    // MARK: - D59 same-mark clears in place

    func testD59_sameMarkClearsInPlace() {
        var machine = CullGrammarMachine(assetCount: 4, columnsPerRow: 4, seed: 1002)
        machine.apply(.focusIndex(0))
        machine.apply(.markKeep)
        XCTAssertEqual(machine.state.marks[asset(machine, at: 0)], .keep)
        XCTAssertEqual(machine.state.focusIndex, 1, "set advances focus")

        machine.apply(.focusIndex(0))
        let focusBeforeClear = machine.state.focusIndex
        machine.apply(.markKeep)
        XCTAssertEqual(machine.state.marks[asset(machine, at: 0)], .undecided)
        XCTAssertEqual(machine.state.focusIndex, focusBeforeClear, "clear stays in place")
    }

    // MARK: - D10 decision keys (toggle grammar; autorepeat is shell-owned)

    func testD10_decisionKeysToggleWithoutAutorepeatSemantics() {
        // D10: each decision press is one toggle; shell swallows key-repeat before events arrive.
        var machine = CullGrammarMachine(assetCount: 3, seed: 1001)
        machine.apply(.markKeep)
        machine.apply(.markReject)
        XCTAssertEqual(machine.state.marks[asset(machine, at: 0)], .keep)
        XCTAssertEqual(machine.state.marks[asset(machine, at: 1)], .reject)
        XCTAssertEqual(machine.state.focusIndex, 2)
        machine.apply(.markKeep)
        XCTAssertEqual(machine.state.marks[asset(machine, at: 2)], .keep)
        machine.apply(.markKeep)
        XCTAssertEqual(machine.state.marks[asset(machine, at: 2)], .undecided)
    }

    // MARK: - D47 / A3 pointer mark parity

    func testD47A3_pointerMarksMatchKeysAndAdvanceIdentically() {
        var keyPath = CullGrammarMachine(assetCount: 4, seed: 2001)
        var pointerPath = CullGrammarMachine(assetCount: 4, seed: 2001)

        keyPath.apply(.markKeep)
        pointerPath.apply(.pointerMarkKeep)
        XCTAssertEqual(keyPath.state, pointerPath.state)

        keyPath.apply(.markReject)
        pointerPath.apply(.pointerMarkReject)
        XCTAssertEqual(keyPath.state, pointerPath.state)
    }

    // MARK: - D11 / D13 Return release never commits

    func testD11D13_releaseNeverCommitsHeldReturn() {
        var machine = CullGrammarMachine(assetCount: 4, seed: 1003)
        machine.apply(.focusIndex(0))
        machine.apply(.markKeep)
        machine.apply(.returnKeyDown(shift: true))
        machine.apply(.returnKeyUp(shift: true))
        XCTAssertTrue(machine.state.staging.active)
        XCTAssertTrue(machine.returnReleaseArmed, "release after ⇧⏎ arms the gate")

        machine.apply(.returnKeyDown(shift: false))
        XCTAssertTrue(machine.returnReleaseArmed, "keyDown alone must not arm release gate")
        XCTAssertTrue(machine.state.staging.active, "stage must survive competing keyDown")

        machine.apply(.returnKeyUp(shift: false))
        XCTAssertTrue(machine.returnReleaseArmed)

        machine.apply(.returnKey(shift: false))
        XCTAssertFalse(machine.state.staging.active, "commit only after physical release")
        XCTAssertEqual(machine.state.undoDepth, 2)
    }

    func testD11D13_shiftReturnKeyDownWithoutReleaseDoesNotCommit() {
        var machine = CullGrammarMachine(assetCount: 4, seed: 1003)
        machine.apply(.markKeep)
        machine.apply(.returnKeyDown(shift: true))
        machine.apply(.returnKey(shift: false))
        XCTAssertTrue(machine.state.staging.active, "held press must never stage-and-commit")
    }

    // MARK: - Esc exact restore

    func testEscRestoresPreStageMarks() {
        var machine = CullGrammarMachine(assetCount: 4, seed: 1004)
        machine.apply(.markKeep)
        machine.apply(.returnKey(shift: true))
        machine.apply(.escape)
        XCTAssertFalse(machine.state.staging.active)
        XCTAssertEqual(machine.state.marks[asset(machine, at: 0)], .keep)
    }

    // MARK: - Undo / travel / arming smoke

    func testUndoRestoresMark() {
        var machine = CullGrammarMachine(assetCount: 3, seed: 1)
        machine.apply(.markKeep)
        machine.apply(.undo)
        XCTAssertEqual(machine.state.marks[asset(machine, at: 0)], .undecided)
        XCTAssertEqual(machine.state.undoDepth, 0)
    }

    func testMoveFocusAndArming() {
        var machine = CullGrammarMachine(assetCount: 8, columnsPerRow: 4, seed: 1005)
        machine.apply(.returnKey(shift: false))
        machine.apply(.tab)
        XCTAssertEqual(machine.state.armedControl, "Exposure")
        XCTAssertFalse(machine.state.staging.active)
        machine.apply(.armDigit(2))
        XCTAssertEqual(machine.state.armedControl, "Contrast")
        machine.apply(.moveFocus(columnDelta: 1, rowDelta: 0))
        XCTAssertEqual(machine.state.focusIndex, 1)
    }

    func testHoldKeysTrackMomentaryState() {
        var machine = CullGrammarMachine(assetCount: 2, seed: 7)
        machine.apply(.holdBegin(.j))
        XCTAssertTrue(machine.state.activeHolds.contains(.j))
        machine.apply(.holdEnd(.j))
        XCTAssertTrue(machine.state.activeHolds.isEmpty)
    }
}
