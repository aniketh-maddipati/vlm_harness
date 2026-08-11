import Foundation
import Observation

/// Staged group action awaiting a second-press confirm. Never commits on first press.
enum StagedAction: Equatable {
    case advance
    case setAside
    case hold
    case treat(DevelopRecipe)
    /// Per-photograph develop proposals — each RAW evaluated independently (hi-fi H4/H5).
    case develop(proposals: [AssetID: EditRecipe])

    var isDevelopStaging: Bool {
        if case .develop = self { return true }
        return false
    }

    var isTreatStaging: Bool {
        if case .treat = self { return true }
        return false
    }
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

    func canConfirm(isARepeat: Bool) -> Bool {
        staged != nil && !isARepeat && !awaitingFreshReturn
    }
}

/// Hand selection + staging for the darkroom table — cross-row, no row scope (hi-fi frame D).
@MainActor
@Observable
final class WorkbenchSelection {
    private(set) var table = TablePhotographSelection()
    private(set) var isHandling = false
    private(set) var staged: StagedAction?
    private(set) var hasEverHandled = false
    private(set) var completedRoundCount = 0
    private(set) var awaitingFreshReturn = false
    /// Wholesale ripple scope — row → scene → shoot (hi-fi H6).
    private(set) var propagation: PropagationState?

    var ids: [AssetID] { table.ids }
    var leader: AssetID? { table.focusID }
    var isEmpty: Bool { table.isEmpty }
    var count: Int { table.count }

    func setHandling(_ down: Bool) {
        if down {
            isHandling = true
            hasEverHandled = true
        } else {
            isHandling = false
        }
    }

    func contains(_ id: AssetID) -> Bool { table.contains(id) }

    /// Plain focus — single photograph selected.
    func focus(_ id: AssetID) {
        table.focus(id)
    }

    /// Toggle member — while staged or ⌘-handling.
    @discardableResult
    func toggle(_ id: AssetID) -> Bool {
        table.toggle(id)
        if staged != nil, table.isEmpty {
            staged = nil
            awaitingFreshReturn = false
        }
        return true
    }

    @discardableResult
    func gather(_ id: AssetID) -> Bool { toggle(id) }

    func rubberBandSelect(_ ids: [AssetID]) {
        table.rubberBand(ids)
    }

    func extendSelection(in tableOrder: [AssetID], to target: AssetID) {
        table.extend(in: tableOrder, to: target)
    }

    func setSelection(_ ids: [AssetID]) {
        table.setMembers(ids)
    }

    func moveLeader(_ delta: Int) {
        guard table.ids.count > 1, let current = table.focusID,
              let index = table.ids.firstIndex(of: current) else { return }
        let next = (index + delta + table.ids.count) % table.ids.count
        table.focusID = table.ids[next]
    }

    @discardableResult
    func stage(_ action: StagedAction) -> Bool {
        guard !table.isEmpty else { return false }
        staged = action
        awaitingFreshReturn = true
        return true
    }

    /// Stage adapt at row ring with propagation scope (hi-fi H6).
    @discardableResult
    func stageTreat(_ recipe: DevelopRecipe, propagation state: PropagationState, memberIDs: [AssetID]) -> Bool {
        guard !memberIDs.isEmpty else { return false }
        propagation = state
        table.setMembers(memberIDs)
        staged = .treat(recipe)
        awaitingFreshReturn = true
        return true
    }

    func syncPropagationMembers(_ memberIDs: [AssetID]) {
        table.setMembers(memberIDs)
    }

    func setPropagation(_ state: PropagationState?) {
        propagation = state
    }

    func noteReturnKeyUp() {
        awaitingFreshReturn = false
    }

    func canConfirm(isARepeat: Bool) -> Bool {
        guard staged != nil, !isARepeat, !awaitingFreshReturn else { return false }
        if staged?.isTreatStaging == true, propagation != nil {
            return !table.isEmpty
        }
        return !table.isEmpty
    }

    func cancel() {
        staged = nil
        propagation = nil
        awaitingFreshReturn = false
    }

    func clearSelection() {
        table.clear()
        staged = nil
        propagation = nil
        awaitingFreshReturn = false
    }

    func markRoundCompleted() {
        completedRoundCount += 1
        clearSelection()
    }

    func clearAfterConfirm() {
        clearSelection()
    }

    var developProposals: [AssetID: EditRecipe]? {
        if case .develop(let proposals) = staged { return proposals }
        return nil
    }

    func updateDevelopStaging(_ proposals: [AssetID: EditRecipe]) {
        guard !proposals.isEmpty else {
            cancel()
            return
        }
        staged = .develop(proposals: proposals)
        awaitingFreshReturn = true
    }

    var shelfLabel: String {
        let n = table.count
        if n <= 0 { return "" }
        if n == 1 { return "1 photograph — one object" }
        return "\(n) photographs — one object"
    }

    var accessibilityAnnouncement: String {
        accessibilityAnnouncement(stagingSnapshot: nil)
    }

    func accessibilityAnnouncement(stagingSnapshot: StagingCopySnapshot?) -> String {
        let n = table.count
        guard n > 0 else { return "No photographs selected" }
        var text = "\(n) photograph\(n == 1 ? "" : "s") selected"
        if let staged {
            switch staged {
            case .advance: text += ", staged to advance"
            case .setAside: text += ", staged to set aside"
            case .hold: text += ", staged to hold"
            case .treat: text += ", staged to treat"
            case .develop: text += ", staged to develop"
            }
        }
        if let stagingSnapshot {
            let ring: String = switch stagingSnapshot.ring {
            case .row: "row ring"
            case .scene: "scene ring"
            case .shoot: "shoot ring"
            }
            text += ", \(ring), \(stagingSnapshot.scopeCount) in scope"
            if stagingSnapshot.excludedCount > 0 {
                text += ", \(stagingSnapshot.excludedCount) excluded"
            }
        }
        return text
    }
}
