import XCTest
@testable import Lumina

@MainActor
final class CommandChordTests: XCTestCase {

    func testHeldReturnCannotDoubleCommit() {
        var gate = CommandChordGate()
        gate.stage(.advance)

        for _ in 0..<60 {
            XCTAssertFalse(gate.canConfirm(isARepeat: true), "held Return must not confirm")
            XCTAssertFalse(gate.canConfirm(isARepeat: false), "confirm blocked until keyUp after stage")
        }

        gate.noteReturnKeyUp()
        XCTAssertTrue(gate.canConfirm(isARepeat: false), "fresh Return after keyUp must confirm")
        XCTAssertFalse(gate.canConfirm(isARepeat: true), "repeat still blocked after keyUp")

        gate.cancel()
        XCTAssertFalse(gate.canConfirm(isARepeat: false), "nothing to confirm after clear")
    }

    func testCancelClearsStagedOnly() {
        var gate = CommandChordGate()
        gate.stage(.setAside)
        gate.cancel()
        XCTAssertNil(gate.staged)
    }
}
