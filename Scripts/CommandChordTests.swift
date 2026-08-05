#!/usr/bin/env swift
/**
 Command-chord auto-repeat defence for the Lumina ⌘ handling layer.
 Mirrors `WorkbenchSelection` confirm gating — run: swift Scripts/CommandChordTests.swift
 */
import Foundation

/// Pure confirm-gating state (mirrors WorkbenchSelection / CommandChordGate).
struct CommandChordGate: Equatable {
    var awaitingFreshReturn = false
    var staged: String?
    var ids: [String] = ["a", "b"]

    mutating func stage(_ action: String) {
        guard !ids.isEmpty else { return }
        staged = action
        awaitingFreshReturn = true
    }

    mutating func noteReturnKeyUp() {
        awaitingFreshReturn = false
    }

    mutating func cancel() {
        staged = nil
        awaitingFreshReturn = false
    }

    func canConfirm(isARepeat: Bool) -> Bool {
        staged != nil && !ids.isEmpty && !isARepeat && !awaitingFreshReturn
    }
}

enum CommandChordTests {
    static func testHeldReturnCannotDoubleCommit() {
        var gate = CommandChordGate()
        gate.stage("advance")

        // Holding Return generates isARepeat keyDown events — must never confirm.
        for _ in 0..<60 {
            precondition(!gate.canConfirm(isARepeat: true), "held Return must not confirm")
            precondition(!gate.canConfirm(isARepeat: false), "confirm blocked until keyUp after stage")
        }

        // First keyUp arms the fresh press.
        gate.noteReturnKeyUp()
        precondition(gate.canConfirm(isARepeat: false), "fresh Return after keyUp must confirm")
        precondition(!gate.canConfirm(isARepeat: true), "repeat still blocked after keyUp")

        // Confirm consumes staged state at the caller; simulate cancel after commit.
        gate.cancel()
        precondition(!gate.canConfirm(isARepeat: false), "nothing to confirm after clear")
    }

    static func testEmptySelectionCannotStage() {
        var gate = CommandChordGate()
        gate.ids = []
        gate.stage("advance")
        precondition(gate.staged == nil, "empty selection must not stage")
        precondition(!gate.canConfirm(isARepeat: false))
    }

    static func testCancelClearsStagedOnly() {
        var gate = CommandChordGate()
        gate.stage("setAside")
        gate.cancel()
        precondition(gate.staged == nil)
        precondition(gate.ids.count == 2, "selection must survive cancel")
    }

    static func runAll() {
        testHeldReturnCannotDoubleCommit()
        testEmptySelectionCannotStage()
        testCancelClearsStagedOnly()
        print("CommandChordTests: all passed")
    }
}

CommandChordTests.runAll()
