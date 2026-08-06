import Foundation

// MARK: - P0 command boundary

/// Shared undoable command surface for cull (now) and later edit/batch commands.
protocol P0Command: Sendable {
    var id: UUID { get }
    var createdAt: Date { get }
    var label: String { get }
}

/// Exact prior/next cull state for one asset — never touches recipes or selection.
struct CullMutationCommand: P0Command, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let assetID: UUID
    let before: CullDecision
    let after: CullDecision
    /// Final-order snapshot before membership reconciliation (for exact undo).
    let finalOrderBefore: [UUID]
    let finalOrderAfter: [UUID]

    var label: String {
        switch after {
        case .keep: return "Keep"
        case .reject: return "Reject"
        case .undecided, .hold: return "Clear decision"
        }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        assetID: UUID,
        before: CullDecision,
        after: CullDecision,
        finalOrderBefore: [UUID],
        finalOrderAfter: [UUID]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.assetID = assetID
        self.before = before
        self.after = after
        self.finalOrderBefore = finalOrderBefore
        self.finalOrderAfter = finalOrderAfter
    }

    /// Toggle grammar: same key clears to unreviewed; otherwise set the decision.
    static func resolveToggle(current: CullDecision, pressed: CullDecision) -> CullDecision {
        if current == pressed { return .undecided }
        return pressed
    }
}

/// Stack-backed undo coordinator — cull today; edit/batch can push the same stack later.
@MainActor
@Observable
final class P0UndoCoordinator {
    private(set) var cullStack: [CullMutationCommand] = []
    private let maxDepth = 64

    var canUndo: Bool { !cullStack.isEmpty }
    var undoLabel: String? { cullStack.last.map { "Undo \($0.label)" } }

    func push(_ command: CullMutationCommand) {
        cullStack.append(command)
        if cullStack.count > maxDepth {
            cullStack.removeFirst(cullStack.count - maxDepth)
        }
    }

    func popCull() -> CullMutationCommand? {
        cullStack.popLast()
    }

    func clear() {
        cullStack.removeAll()
    }
}

// MARK: - Kept-membership reconciliation

extension FinalSetOrder {
    /// Canonical policy: when a custom order exists, membership tracks Keep;
    /// chronological mode (empty) stays empty so export derives from kept cull alone.
    mutating func reconcileKeptMembership(keptIDsInChronologicalOrder: [UUID]) {
        guard isCustom else { return }
        let kept = Set(keptIDsInChronologicalOrder)
        assetIDs.removeAll { !kept.contains($0) }
        for id in keptIDsInChronologicalOrder where !assetIDs.contains(id) {
            assetIDs.append(id)
        }
    }
}
