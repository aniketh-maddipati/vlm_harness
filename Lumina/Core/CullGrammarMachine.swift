import Foundation

// MARK: - Events

/// Headless cull / edit-travel grammar input — no coordinates, no wall clock.
enum CullGrammarEvent: Equatable, Sendable {
    case markKeep
    case markReject
    case pointerMarkKeep
    case pointerMarkReject
    case focusIndex(Int)
    case moveFocus(columnDelta: Int, rowDelta: Int)
    case returnKeyDown(shift: Bool)
    case returnKeyUp(shift: Bool)
    case returnKey(shift: Bool)
    case escape
    case undo
    case tab
    case armDigit(Int)
    case armControl(String)
    case holdBegin(CullHoldKey)
    case holdEnd(CullHoldKey)
}

enum CullHoldKey: String, Equatable, Sendable, CaseIterable {
    case space
    case question
    case j
}

// MARK: - State

struct CullGrammarStaging: Equatable, Sendable {
    var active: Bool = false
    var ring: PropagationRing = .row
    var scopeCount: Int = 0
    var excludedCount: Int = 0
    var bannerCount: Int = 0
    var headerCount: Int = 0
    var receiptCount: Int = 0
    var returnReleaseArmed: Bool = false

    static let idle = CullGrammarStaging()
}

struct CullGrammarSnapshot: Equatable, Sendable {
    var marks: [UUID: CullDecision]
    var focusIndex: Int
    var staging: CullGrammarStaging
    var armedControl: String?
}

/// Pure cull-grammar state — marks, focus, staging ring, arming, undo depth.
struct CullGrammarState: Equatable, Sendable {
    var assetIDs: [UUID]
    var columnsPerRow: Int
    var marks: [UUID: CullDecision]
    var focusIndex: Int
    var staging: CullGrammarStaging
    var armedControl: String?
    var activeHolds: Set<CullHoldKey>
    var undoStack: [CullGrammarSnapshot]

    var undoDepth: Int { undoStack.count }

    var focusedAssetID: UUID? {
        guard focusIndex >= 0, focusIndex < assetIDs.count else { return nil }
        return assetIDs[focusIndex]
    }

    static func make(assetCount: Int, columnsPerRow: Int = 4, seed: UInt64 = 0) -> CullGrammarState {
        var ids: [UUID] = []
        ids.reserveCapacity(assetCount)
        for index in 0..<assetCount {
            var bytes = [UInt8](repeating: 0, count: 16)
            let tag = seed &+ UInt64(index &* 997) &+ 0xA0
            for byteIndex in 0..<8 {
                bytes[byteIndex] = UInt8(truncatingIfNeeded: tag >> (byteIndex * 8))
            }
            bytes[15] = UInt8(truncatingIfNeeded: index)
            ids.append(UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )))
        }
        let marks = Dictionary(uniqueKeysWithValues: ids.map { ($0, CullDecision.undecided) })
        return CullGrammarState(
            assetIDs: ids,
            columnsPerRow: max(columnsPerRow, 1),
            marks: marks,
            focusIndex: 0,
            staging: .idle,
            armedControl: nil,
            activeHolds: [],
            undoStack: []
        )
    }
}

// MARK: - Machine

/// Event → state reducer for the cull hot loop and adjacent travel grammar.
struct CullGrammarMachine: Equatable, Sendable {
    private(set) var state: CullGrammarState
    private var returnHeldAfterShift = false
    private var preStageSnapshot: CullGrammarSnapshot?

    init(state: CullGrammarState) {
        self.state = state
    }

    init(assetCount: Int, columnsPerRow: Int = 4, seed: UInt64 = 0) {
        self.state = .make(assetCount: assetCount, columnsPerRow: columnsPerRow, seed: seed)
    }

    mutating func apply(_ event: CullGrammarEvent) {
        switch event {
        case .markKeep:
            applyMark(pressed: .keep)
        case .markReject:
            applyMark(pressed: .reject)
        case .pointerMarkKeep:
            applyMark(pressed: .keep)
        case .pointerMarkReject:
            applyMark(pressed: .reject)
        case .focusIndex(let index):
            setFocusIndex(index)
        case .moveFocus(let columnDelta, let rowDelta):
            moveFocus(columnDelta: columnDelta, rowDelta: rowDelta)
        case .returnKeyDown(let shift):
            applyReturnKeyDown(shift: shift)
        case .returnKeyUp(let shift):
            applyReturnKeyUp(shift: shift)
        case .returnKey(let shift):
            applyReturnKey(shift: shift)
        case .escape:
            applyEscape()
        case .undo:
            applyUndo()
        case .tab:
            armControl(Self.defaultArmedControl)
        case .armDigit(let digit):
            guard (1...4).contains(digit) else { return }
            armControl(Self.railControls[digit - 1])
        case .armControl(let control):
            armControl(control)
        case .holdBegin(let key):
            state.activeHolds.insert(key)
        case .holdEnd(let key):
            state.activeHolds.remove(key)
        }
    }

    // MARK: - Mark (P / X / pointer parity — D47/A3)

    private mutating func applyMark(pressed: CullDecision) {
        guard let assetID = state.focusedAssetID else { return }
        let before = state.marks[assetID] ?? .undecided
        let after = CullMutationCommand.resolveToggle(current: before, pressed: pressed)
        guard before != after else { return }
        pushUndo()
        state.marks[assetID] = after
        if after != .undecided {
            advanceFocusAfterMarkSet()
        }
    }

    private mutating func advanceFocusAfterMarkSet() {
        guard state.focusIndex + 1 < state.assetIDs.count else { return }
        state.focusIndex += 1
    }

    // MARK: - Focus travel

    private mutating func setFocusIndex(_ index: Int) {
        guard !state.assetIDs.isEmpty else { return }
        state.focusIndex = min(max(index, 0), state.assetIDs.count - 1)
    }

    private mutating func moveFocus(columnDelta: Int, rowDelta: Int) {
        let cols = state.columnsPerRow
        let count = state.assetIDs.count
        guard count > 0 else { return }
        let row = state.focusIndex / cols
        let col = state.focusIndex % cols
        let newRow = max(0, row + rowDelta)
        let newCol = min(max(0, col + columnDelta), cols - 1)
        var next = newRow * cols + newCol
        if next >= count { next = count - 1 }
        state.focusIndex = next
    }

    // MARK: - Return / Shift-Return (D11 / D13 / D60)

    private mutating func applyReturnKeyDown(shift: Bool) {
        if shift {
            stageRow()
            returnHeldAfterShift = true
            state.staging.returnReleaseArmed = false
            return
        }
        // Plain Return keyDown never commits (D13 release never commits).
    }

    private mutating func applyReturnKeyUp(shift: Bool) {
        _ = shift
        if returnHeldAfterShift || state.staging.active {
            state.staging.returnReleaseArmed = true
            returnHeldAfterShift = false
        }
    }

    private mutating func applyReturnKey(shift: Bool) {
        if shift {
            stageRow()
            state.staging.returnReleaseArmed = true
            return
        }
        if state.staging.active {
            guard state.staging.returnReleaseArmed else { return }
            commitStage()
            return
        }
        state.armedControl = nil
    }

    // MARK: - Esc (L5 / D11)

    private mutating func applyEscape() {
        if state.staging.active, let snapshot = preStageSnapshot {
            state.marks = snapshot.marks
            state.focusIndex = snapshot.focusIndex
            state.staging = snapshot.staging
            state.armedControl = snapshot.armedControl
            preStageSnapshot = nil
            return
        }
        state.armedControl = nil
    }

    // MARK: - Undo

    private mutating func applyUndo() {
        guard let snapshot = state.undoStack.popLast() else { return }
        state.marks = snapshot.marks
        state.focusIndex = snapshot.focusIndex
        state.staging = snapshot.staging
        state.armedControl = snapshot.armedControl
        if !state.staging.active {
            preStageSnapshot = nil
        }
    }

    // MARK: - Arming (D24)

    private mutating func armControl(_ control: String) {
        state.armedControl = control
    }

    // MARK: - Staging helpers

    private mutating func stageRow() {
        if preStageSnapshot == nil {
            preStageSnapshot = currentSnapshot()
        }
        let focusRow = row(of: state.focusIndex)
        let keptInRow = state.assetIDs.enumerated().compactMap { index, id -> UUID? in
            guard row(of: index) == focusRow, state.marks[id] == .keep else { return nil }
            return id
        }
        let scope: [UUID]
        if keptInRow.isEmpty, let focus = state.focusedAssetID {
            scope = [focus]
        } else {
            scope = keptInRow
        }
        let count = scope.count
        state.staging = CullGrammarStaging(
            active: true,
            ring: .row,
            scopeCount: count,
            excludedCount: 0,
            bannerCount: count,
            headerCount: count,
            receiptCount: count,
            returnReleaseArmed: false
        )
    }

    private mutating func commitStage() {
        pushUndo()
        state.staging = .idle
        preStageSnapshot = nil
    }

    private mutating func pushUndo() {
        state.undoStack.append(currentSnapshot())
        if state.undoStack.count > 64 {
            state.undoStack.removeFirst(state.undoStack.count - 64)
        }
    }

    private func currentSnapshot() -> CullGrammarSnapshot {
        CullGrammarSnapshot(
            marks: state.marks,
            focusIndex: state.focusIndex,
            staging: state.staging,
            armedControl: state.armedControl
        )
    }

    private func row(of index: Int) -> Int {
        index / state.columnsPerRow
    }

    private static let railControls = ["Exposure", "Contrast", "Highlights", "Shadows"]
    private static let defaultArmedControl = "Exposure"
}

extension CullGrammarMachine {
    /// True after Return release following a staged ⇧⏎ — commit requires this (D60).
    var returnReleaseArmed: Bool { state.staging.returnReleaseArmed }
}
