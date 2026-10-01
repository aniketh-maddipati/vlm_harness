import Foundation
import Observation

// WP-5. Edits per photo, or per burst when two or more of its frames are kept, with Edit's own
// undo and redo, 200 deep (R-27). Only values that differ from a setting's default are stored,
// so 300 edited photos stay far below 2 MB (R-86).

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
    /// Bumped on every change to the looks or to the history (the undo and redo buttons watch it).
    public private(set) var revision = 0
    @ObservationIgnored private var undoStack: [Entry] = []
    @ObservationIgnored private var redoStack: [Entry] = []
    /// The look key whose top undo entry a coalescing change may still fold into (one drag).
    @ObservationIgnored private var openKey: String?

    public init(shoot: Shoot, looks: [String: Look] = [:], tags: [String: String] = [:], done: Set<String> = []) {
        self.shoot = shoot; self.looks = looks.compactMapValues { let c = Self.clean($0); return c.isEmpty ? nil : c }
        self.tags = tags; self.done = done
    }

    public var canUndo: Bool { _ = revision; return !undoStack.isEmpty }
    public var canRedo: Bool { _ = revision; return !redoStack.isEmpty }
    public var undoCount: Int { _ = revision; return undoStack.count }

    /// The photo id, or its burst's id when 2+ frames of the burst are kept.
    public func key(for id: String, decisions: DecisionStore) -> String {
        guard let b = shoot.burst(shoot.photo(id)?.burst), b.ids.contains(id) else { return id }
        var kept = 0
        for f in b.ids where decisions.keep[f] == true { kept += 1; if kept >= 2 { return b.id } }
        return id
    }
    /// How many kept frames share this photo's edit (1 outside a burst).
    public func sharedBy(_ id: String, decisions: DecisionStore) -> Int {
        guard let b = shoot.burst(shoot.photo(id)?.burst) else { return 1 }
        return max(1, b.ids.filter { decisions.keep[$0] == true }.count)
    }
    public func look(_ id: String, decisions: DecisionStore) -> Look { looks[key(for: id, decisions: decisions)] ?? [:] }
    public func isEdited(_ id: String, decisions: DecisionStore) -> Bool { !look(id, decisions: decisions).isEmpty }

    /// Set one setting (nil or the default removes it). `coalesce` folds the change into the
    /// undo step of the drag in progress (a drag is one step).
    public func set(_ setting: String, _ value: Double?, on id: String, decisions: DecisionStore, coalesce: Bool = false) {
        var l = look(id, decisions: decisions)
        if let v = value, v != EditSetting.byKey[setting]?.def { l[setting] = v } else { l[setting] = nil }
        setLook(l, on: id, decisions: decisions, coalesce: coalesce)
    }

    public func setLook(_ new: Look, on id: String, decisions: DecisionStore, coalesce: Bool = false) {
        let k = key(for: id, decisions: decisions), old = looks[k] ?? [:], new = Self.clean(new)
        guard old != new else { return }
        looks[k] = new.isEmpty ? nil : new
        if coalesce, openKey == k, let last = undoStack.last, last.key == k, last.decision == nil {
            // Back where the drag started: the step would undo nothing, so it goes.
            if last.before == new { undoStack.removeLast() } else { undoStack[undoStack.count - 1].after = new }
        } else {
            push(Entry(key: k, before: old, after: new, photo: id, decision: nil))
            openKey = coalesce ? k : nil
        }
        revision &+= 1
    }

    /// A drag starts: its first change is a new undo step, never folded into an older one.
    public func beginCoalescing() { openKey = nil }
    /// The drag is over: later changes are their own steps.
    public func endCoalescing() { openKey = nil }

    /// Record an Out made in Edit so Edit's ⌘Z restores it.
    public func recordDecision(_ item: DecisionStore.Change.Item, photo: String) {
        push(Entry(key: "", before: [:], after: [:], photo: photo, decision: item)); openKey = nil; revision &+= 1
    }

    @discardableResult public func undo() -> Entry? {
        guard let e = undoStack.popLast() else { return nil }
        if e.decision == nil { looks[e.key] = e.before.isEmpty ? nil : e.before }
        redoStack.append(e); openKey = nil; revision &+= 1; return e
    }
    @discardableResult public func redo() -> Entry? {
        guard let e = redoStack.popLast() else { return nil }
        if e.decision == nil { looks[e.key] = e.after.isEmpty ? nil : e.after }
        undoStack.append(e); openKey = nil; revision &+= 1; return e
    }
    private func push(_ e: Entry) { undoStack.append(e); if undoStack.count > Self.depth { undoStack.removeFirst() }; redoStack.removeAll() }

    /// Size of the stored edits as JSON (R-86).
    public var lookBytes: Int { (try? JSONEncoder().encode(looks).count) ?? 0 }

    /// A look with nothing in it that equals a default, and no value that isn't a number (R-53, R-86).
    public static func clean(_ look: Look) -> Look {
        look.filter { k, v in v.isFinite && EditSetting.byKey[k].map { $0.def != v } ?? true }
    }
}
