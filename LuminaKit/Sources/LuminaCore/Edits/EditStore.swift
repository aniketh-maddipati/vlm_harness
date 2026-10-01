import Foundation
import Observation

// WP-5. Edits per photo, or per burst when two or more of its frames are kept, with Edit's own
// undo and redo, 200 deep (R-27).

@Observable
public final class EditStore: @unchecked Sendable {
    public struct Entry: Equatable, Sendable {
        public var key: String
        public var before: Look, after: Look
        /// The Edit photo when the change was made; undo goes back to it.
        public var photo: String
        /// An Out made in Edit travels with Edit's history (⌘Z brings the photo back, R-28).
        public var decision: DecisionStore.Change.Item?
    }
    public static let depth = 200

    public let shoot: Shoot
    public private(set) var looks: [String: Look]
    public var tags: [String: String]
    public var done: Set<String>
    public private(set) var revision = 0
    @ObservationIgnored private var undoStack: [Entry] = []
    @ObservationIgnored private var redoStack: [Entry] = []

    public init(shoot: Shoot, looks: [String: Look] = [:], tags: [String: String] = [:], done: Set<String> = []) {
        self.shoot = shoot; self.looks = looks; self.tags = tags; self.done = done
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// The photo id, or its burst's id when 2+ frames of the burst are kept.
    public func key(for id: String, decisions: DecisionStore) -> String {
        guard let b = shoot.burst(shoot.photo(id)?.burst), b.ids.filter({ decisions.keep[$0] == true }).count >= 2 else { return id }
        return b.id
    }
    public func look(_ id: String, decisions: DecisionStore) -> Look { looks[key(for: id, decisions: decisions)] ?? [:] }
    public func isEdited(_ id: String, decisions: DecisionStore) -> Bool { !look(id, decisions: decisions).isEmpty }

    /// Set one setting (nil or the default removes it). `coalesce` folds the change into the
    /// previous undo step for the same key (a drag is one step).
    public func set(_ setting: String, _ value: Double?, on id: String, decisions: DecisionStore, coalesce: Bool = false) {
        var l = look(id, decisions: decisions)
        if let v = value, v != EditSetting.byKey[setting]?.def { l[setting] = v } else { l[setting] = nil }
        setLook(l, on: id, decisions: decisions, coalesce: coalesce)
    }

    public func setLook(_ new: Look, on id: String, decisions: DecisionStore, coalesce: Bool = false) {
        let k = key(for: id, decisions: decisions), old = looks[k] ?? [:]
        guard old != new else { return }
        looks[k] = new.isEmpty ? nil : new
        if coalesce, let last = undoStack.last, last.key == k, last.decision == nil { undoStack[undoStack.count - 1].after = new }
        else { push(Entry(key: k, before: old, after: new, photo: id, decision: nil)) }
        revision &+= 1
    }

    /// Record an Out made in Edit so Edit's ⌘Z restores it.
    public func recordDecision(_ item: DecisionStore.Change.Item, photo: String) {
        push(Entry(key: "", before: [:], after: [:], photo: photo, decision: item))
    }

    @discardableResult public func undo() -> Entry? {
        guard let e = undoStack.popLast() else { return nil }
        if e.decision == nil { looks[e.key] = e.before.isEmpty ? nil : e.before; revision &+= 1 }
        redoStack.append(e); return e
    }
    @discardableResult public func redo() -> Entry? {
        guard let e = redoStack.popLast() else { return nil }
        if e.decision == nil { looks[e.key] = e.after.isEmpty ? nil : e.after; revision &+= 1 }
        undoStack.append(e); return e
    }
    private func push(_ e: Entry) { undoStack.append(e); if undoStack.count > Self.depth { undoStack.removeFirst() }; redoStack.removeAll() }

    /// Size of the stored edits as JSON (R-86).
    public var lookBytes: Int { (try? JSONEncoder().encode(looks).count) ?? 0 }
}
