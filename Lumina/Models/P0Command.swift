import Foundation

// MARK: - P0 command boundary

/// Exact prior/next cull state for one asset — never touches recipes or selection.
struct CullMutationCommand: Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let assetID: UUID
    let before: CullDecision
    let after: CullDecision
    let userDecidedAtBefore: Date?
    let userDecidedAtAfter: Date?
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
        userDecidedAtBefore: Date? = nil,
        userDecidedAtAfter: Date? = nil,
        finalOrderBefore: [UUID],
        finalOrderAfter: [UUID]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.assetID = assetID
        self.before = before
        self.after = after
        self.userDecidedAtBefore = before == .undecided ? nil : (userDecidedAtBefore ?? createdAt)
        self.userDecidedAtAfter = after == .undecided ? nil : (userDecidedAtAfter ?? createdAt)
        self.finalOrderBefore = finalOrderBefore
        self.finalOrderAfter = finalOrderAfter
    }

    @discardableResult
    func apply(to assets: inout [AssetRecord], finalOrder: inout FinalSetOrder) -> Bool {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return false }
        assets[index].cull = after
        assets[index].userDecidedAt = userDecidedAtAfter
        finalOrder.assetIDs = finalOrderAfter
        return true
    }

    @discardableResult
    func revert(in assets: inout [AssetRecord], finalOrder: inout FinalSetOrder) -> Bool {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return false }
        assets[index].cull = before
        assets[index].userDecidedAt = userDecidedAtBefore
        finalOrder.assetIDs = finalOrderBefore
        return true
    }

    func reversed(id: UUID = UUID(), createdAt: Date = Date()) -> CullMutationCommand {
        CullMutationCommand(
            id: id,
            createdAt: createdAt,
            assetID: assetID,
            before: after,
            after: before,
            userDecidedAtBefore: userDecidedAtAfter,
            userDecidedAtAfter: userDecidedAtBefore,
            finalOrderBefore: finalOrderAfter,
            finalOrderAfter: finalOrderBefore
        )
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
struct EditMutationCommand: Equatable, Sendable {
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

    @discardableResult
    func apply(to assets: inout [AssetRecord]) -> Bool {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return false }
        assets[index].recipe = after.hasSettings ? after : nil
        return true
    }

    @discardableResult
    func revert(in assets: inout [AssetRecord]) -> Bool {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return false }
        assets[index].recipe = before.hasSettings ? before : nil
        return true
    }

    func reversed(id: UUID = UUID(), createdAt: Date = Date()) -> EditMutationCommand {
        EditMutationCommand(
            id: id,
            createdAt: createdAt,
            assetID: assetID,
            before: after,
            after: before
        )
    }
}

/// One keep-this-burst move — every mark in the chapter restores together.
struct ChapterKeepCommand: Equatable, Sendable {
    struct Mark: Equatable, Sendable {
        var assetID: UUID
        var before: CullDecision
        var after: CullDecision
        var userDecidedAtBefore: Date? = nil
        var userDecidedAtAfter: Date? = nil
    }

    let id: UUID
    let createdAt: Date
    let marks: [Mark]
    let finalOrderBefore: [UUID]
    let finalOrderAfter: [UUID]
    let chapterBefore: String?
    let focusBefore: UUID?
    let burstID: String

    var label: String { "Keep burst" }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        marks: [Mark],
        finalOrderBefore: [UUID],
        finalOrderAfter: [UUID],
        chapterBefore: String?,
        focusBefore: UUID?,
        burstID: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.marks = marks
        self.finalOrderBefore = finalOrderBefore
        self.finalOrderAfter = finalOrderAfter
        self.chapterBefore = chapterBefore
        self.focusBefore = focusBefore
        self.burstID = burstID
    }

    @discardableResult
    func apply(to assets: inout [AssetRecord], finalOrder: inout FinalSetOrder) -> Bool {
        var changed = false
        for mark in marks {
            guard let index = assets.firstIndex(where: { $0.id == mark.assetID }) else { continue }
            assets[index].cull = mark.after
            assets[index].userDecidedAt = mark.after == .undecided
                ? nil
                : (mark.userDecidedAtAfter ?? createdAt)
            changed = true
        }
        guard changed else { return false }
        finalOrder.assetIDs = finalOrderAfter
        return true
    }

    @discardableResult
    func revert(in assets: inout [AssetRecord], finalOrder: inout FinalSetOrder) -> Bool {
        var changed = false
        for mark in marks {
            guard let index = assets.firstIndex(where: { $0.id == mark.assetID }) else { continue }
            assets[index].cull = mark.before
            assets[index].userDecidedAt = mark.before == .undecided
                ? nil
                : (mark.userDecidedAtBefore ?? createdAt)
            changed = true
        }
        guard changed else { return false }
        finalOrder.assetIDs = finalOrderBefore
        return true
    }
}

/// Heterogeneous undo entry on the shared P0 command stack.
enum P0UndoEntry: Equatable, Sendable {
    case cull(CullMutationCommand)
    case edit(EditMutationCommand)
    case chapterKeep(ChapterKeepCommand)

    var label: String {
        switch self {
        case .cull(let command): return command.label
        case .edit(let command): return command.label
        case .chapterKeep(let command): return command.label
        }
    }
}

/// Stack-backed undo coordinator shared by cull and edit commands.
@MainActor
@Observable
final class P0UndoCoordinator {
    private(set) var stack: [P0UndoEntry] = []

    private let maxDepth = 64

    var canUndo: Bool { !stack.isEmpty }
    var undoLabel: String? { stack.last.map { "Undo \($0.label)" } }

    func push(_ command: CullMutationCommand) {
        append(.cull(command))
    }

    func push(_ command: EditMutationCommand) {
        append(.edit(command))
    }

    func push(_ command: ChapterKeepCommand) {
        append(.chapterKeep(command))
    }

    func pop() -> P0UndoEntry? {
        stack.popLast()
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
