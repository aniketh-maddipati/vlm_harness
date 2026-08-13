import Foundation

// MARK: - P0 command boundary

/// Shared undoable command surface for cull and edit mutations.
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

/// D10 / D47 — linear focus advance after a committed cull mark (D59: caller gates on `after != .undecided`).
enum CullFocusAdvance {
    static func nextIndex(after markedIndex: Int, count: Int) -> Int? {
        let next = markedIndex + 1
        guard next < count else { return nil }
        return next
    }

    static func nextID(after markedID: UUID, in orderedIDs: [UUID]) -> UUID? {
        guard let index = orderedIDs.firstIndex(of: markedID),
              let next = nextIndex(after: index, count: orderedIDs.count) else { return nil }
        return orderedIDs[next]
    }
}

/// Exact prior/next recipe for one asset — never touches cull, selection, or final order.
struct EditMutationCommand: P0Command, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let assetID: UUID
    let before: EditRecipe
    let after: EditRecipe

    var label: String {
        if !after.hasSettings, before.hasSettings { return "Reset edit" }
        if after.geometryIntent != before.geometryIntent { return "Crop" }
        return "Edit"
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        assetID: UUID,
        before: EditRecipe,
        after: EditRecipe
    ) {
        self.id = id
        self.createdAt = createdAt
        self.assetID = assetID
        self.before = before
        self.after = after
    }
}

/// Heterogeneous undo entry on the shared P0 command stack.
enum P0UndoEntry: Equatable, Sendable {
    case cull(CullMutationCommand)
    case edit(EditMutationCommand)

    var label: String {
        switch self {
        case .cull(let command): return command.label
        case .edit(let command): return command.label
        }
    }
}

/// Stack-backed undo coordinator shared by cull and edit commands.
@MainActor
@Observable
final class P0UndoCoordinator {
    private(set) var stack: [P0UndoEntry] = []
    /// Compatibility mirror of cull-only entries for existing call sites / tests.
    var cullStack: [CullMutationCommand] {
        stack.compactMap {
            if case .cull(let command) = $0 { return command }
            return nil
        }
    }

    private let maxDepth = 64

    var canUndo: Bool { !stack.isEmpty }
    var undoLabel: String? { stack.last.map { "Undo \($0.label)" } }

    func push(_ command: CullMutationCommand) {
        append(.cull(command))
    }

    func push(_ command: EditMutationCommand) {
        append(.edit(command))
    }

    func pop() -> P0UndoEntry? {
        stack.popLast()
    }

    /// Legacy cull-only pop — returns nil when the top entry is an edit.
    func popCull() -> CullMutationCommand? {
        guard case .cull(let command) = stack.last else { return nil }
        _ = stack.popLast()
        return command
    }

    func clear() {
        stack.removeAll()
    }

    private func append(_ entry: P0UndoEntry) {
        stack.append(entry)
        if stack.count > maxDepth {
            stack.removeFirst(stack.count - maxDepth)
        }
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
