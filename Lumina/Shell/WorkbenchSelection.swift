import Foundation
import Observation

/// Staged group action awaiting a second-press confirm. Never commits on first press.
enum StagedAction: Equatable {
    case advance
    case setAside
    case hold
    case treat(DevelopRecipe)
}

/// One undoable round of workbench decisions — one receipt, one ledger transaction.
struct RoundReceipt: Equatable, Identifiable {
    let id: UUID
    let text: String
    let entries: [DecisionLedgerEntry]
    let priorEmergingOrder: [AssetID]
}

/// Per-photograph restore payload for a single round entry.
struct DecisionLedgerEntry: Equatable, Identifiable {
    let id: UUID
    let photoID: AssetID
    let priorTier: PhotoTier
    let priorFlagged: Bool
    let priorUncertaintyKind: UncertaintyKind
    let priorWhyUncertain: String?
    let applied: AssetDecision
    let priorRecipe: DevelopRecipe?
    let appliedRecipe: DevelopRecipe?
    /// Canonical edit recipe before a geometry commit (crop undo).
    let priorEditRecipe: EditRecipe?

    init(
        id: UUID = UUID(),
        photoID: AssetID,
        priorTier: PhotoTier,
        priorFlagged: Bool,
        priorUncertaintyKind: UncertaintyKind,
        priorWhyUncertain: String?,
        applied: AssetDecision,
        priorRecipe: DevelopRecipe? = nil,
        appliedRecipe: DevelopRecipe? = nil,
        priorEditRecipe: EditRecipe? = nil
    ) {
        self.id = id
        self.photoID = photoID
        self.priorTier = priorTier
        self.priorFlagged = priorFlagged
        self.priorUncertaintyKind = priorUncertaintyKind
        self.priorWhyUncertain = priorWhyUncertain
        self.applied = applied
        self.priorRecipe = priorRecipe
        self.appliedRecipe = appliedRecipe
        self.priorEditRecipe = priorEditRecipe
    }
}

/// Pure confirm-gating state for the two-beat Return chord (unit-testable).
struct CommandChordGate: Equatable {
    /// Set `true` when an action is staged; cleared on the first Return keyUp.
    var awaitingFreshReturn = false
    var staged: StagedAction?

    mutating func stage(_ action: StagedAction) {
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

    /// Confirm only on a fresh (non-repeat) Return after a keyUp since staging.
    func canConfirm(isARepeat: Bool) -> Bool {
        staged != nil && !isARepeat && !awaitingFreshReturn
    }
}

/// Ordered gathering model for the darkroom table. Cap 3; ⌘ is an anchor, not a command.
@MainActor
@Observable
final class WorkbenchSelection {
    private(set) var ids: [AssetID] = []
    private(set) var leader: AssetID?
    private(set) var isHandling = false
    private(set) var staged: StagedAction?
    /// True after the photographer has pressed ⌘ at least once this session.
    private(set) var hasEverHandled = false
    /// Completed rounds this session — hint fades after the third.
    private(set) var completedRoundCount = 0
    /// Auto-repeat defence — set on stage, cleared on Return keyUp.
    private(set) var awaitingFreshReturn = false

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    func setHandling(_ down: Bool) {
        if down {
            isHandling = true
            hasEverHandled = true
        } else {
            // Releasing ⌘ never clears selection, never commits, never cancels.
            isHandling = false
        }
    }

    /// Toggle membership. Cap 3 — a 4th replaces the oldest.
    @discardableResult
    func gather(_ id: AssetID) -> Bool {
        if let existing = ids.firstIndex(of: id) {
            ids.remove(at: existing)
            if leader == id {
                leader = ids.last
            }
            if staged != nil, ids.isEmpty {
                staged = nil
                awaitingFreshReturn = false
            }
            return true
        }

        if ids.count >= 3 {
            ids.removeFirst()
            LuminaHaptics.alignment()
        }
        ids.append(id)
        leader = id
        return true
    }

    func contains(_ id: AssetID) -> Bool {
        ids.contains(id)
    }

    /// Cycle leader inside the selection without dropping membership.
    func moveLeader(_ delta: Int) {
        guard ids.count > 1, let current = leader,
              let index = ids.firstIndex(of: current) else { return }
        let next = (index + delta + ids.count) % ids.count
        leader = ids[next]
    }

    /// Stage a group action. Empty selection cannot stage — returns false.
    @discardableResult
    func stage(_ action: StagedAction) -> Bool {
        guard !ids.isEmpty else { return false }
        staged = action
        awaitingFreshReturn = true
        return true
    }

    func noteReturnKeyUp() {
        awaitingFreshReturn = false
    }

    /// Confirm only on a fresh (non-repeat) Return after a keyUp since staging.
    func canConfirm(isARepeat: Bool) -> Bool {
        staged != nil && !ids.isEmpty && !isARepeat && !awaitingFreshReturn
    }

    /// Clears staged only. Selection survives.
    func cancel() {
        staged = nil
        awaitingFreshReturn = false
    }

    /// Escape with nothing staged clears the selection.
    func clearSelection() {
        ids = []
        leader = nil
        staged = nil
        awaitingFreshReturn = false
    }

    func markRoundCompleted() {
        completedRoundCount += 1
        staged = nil
        ids = []
        leader = nil
        awaitingFreshReturn = false
    }

    func clearAfterConfirm() {
        staged = nil
        ids = []
        leader = nil
        awaitingFreshReturn = false
    }

    var shelfLabel: String {
        let n = ids.count
        if n <= 0 { return "" }
        if n == 1 { return "1 photograph — one object" }
        return "\(n) photographs — one object"
    }

    var accessibilityAnnouncement: String {
        let n = ids.count
        guard n > 0 else { return "No photographs gathered" }
        var text = "\(n) photograph\(n == 1 ? "" : "s") gathered"
        if let staged {
            switch staged {
            case .advance: text += ", staged to advance"
            case .setAside: text += ", staged to set aside"
            case .hold: text += ", staged to hold"
            case .treat: text += ", staged to treat"
            }
        }
        return text
    }
}
