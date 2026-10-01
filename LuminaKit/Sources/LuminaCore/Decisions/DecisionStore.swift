import Foundation
import Observation

// WP-3. Keep / Out decisions with exact undo and redo, 200 deep (R-04, R-05).

@Observable
public final class DecisionStore: @unchecked Sendable {
    /// One undo step: one or more photos changed together (Keep suggested is one step).
    public struct Change: Equatable, Sendable {
        public var items: [Item]
        /// The photo to go back to when this step is undone (or redone): Cull's current photo
        /// when the decision was made, or when it was undone (parity traces).
        public var cur: String?
        public struct Item: Equatable, Sendable { public var id: String; public var before: Bool?; public var after: Bool? }
    }
    public static let depth = 200

    public private(set) var keep: [String: Bool]
    public private(set) var keptCount = 0
    public private(set) var outCount = 0
    /// Bumped on every change; caches key on it.
    public private(set) var revision = 0
    public let ids: [String]
    @ObservationIgnored private var undoStack: [Change] = []
    @ObservationIgnored private var redoStack: [Change] = []

    public init(ids: [String], keep: [String: Bool] = [:]) {
        self.ids = ids; self.keep = keep
        keptCount = keep.values.filter { $0 }.count; outCount = keep.count - keptCount
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// true = keep, false = out, nil = undecided. Never a half-state: one assignment.
    public func mark(_ id: String, keep value: Bool?, cur: String? = nil) { mark([id], keep: value, cur: cur) }

    public func mark(_ ids: [String], keep value: Bool?, cur: String? = nil) {
        let items = ids.compactMap { id -> Change.Item? in keep[id] == value ? nil : .init(id: id, before: keep[id], after: value) }
        guard !items.isEmpty else { return }
        apply(items, forward: true)
        push(Change(items: items, cur: cur))
    }

    /// A key press on a photo (R / X in Cull). Always one undo step, even when the photo already
    /// had that decision, so ⌘Z after it goes back to the photo the key was pressed on instead of
    /// silently undoing an older decision somewhere else.
    public func decide(_ id: String, keep value: Bool, cur: String?) {
        let items: [Change.Item] = keep[id] == value ? [] : [.init(id: id, before: keep[id], after: value)]
        if !items.isEmpty { apply(items, forward: true) }
        push(Change(items: items, cur: cur))
    }

    /// Change a decision without history (Edit's Out and its undo own their history, R-08, R-27).
    public func set(_ id: String, keep value: Bool?) {
        guard keep[id] != value else { return }
        apply([.init(id: id, before: keep[id], after: value)], forward: true)
    }

    @discardableResult public func undo() -> Change? {
        guard let c = undoStack.popLast() else { return nil }
        apply(c.items, forward: false); redoStack.append(c); return c
    }
    @discardableResult public func redo() -> Change? {
        guard let c = redoStack.popLast() else { return nil }
        apply(c.items, forward: true); undoStack.append(c); return c
    }

    /// Undo from Cull: the returned step's `cur` is the photo to show again, and redoing it later
    /// comes back to `current`, the photo that was on screen when ⌘Z was pressed.
    @discardableResult public func undo(from current: String?) -> Change? {
        guard let c = undoStack.popLast() else { return nil }
        apply(c.items, forward: false); redoStack.append(Change(items: c.items, cur: current)); return c
    }
    /// Redo from Cull: the mirror of `undo(from:)`.
    @discardableResult public func redo(from current: String?) -> Change? {
        guard let c = redoStack.popLast() else { return nil }
        apply(c.items, forward: true); undoStack.append(Change(items: c.items, cur: current)); return c
    }

    public func resetHistory() { undoStack.removeAll(); redoStack.removeAll() }
    public func clear() { keep = [:]; keptCount = 0; outCount = 0; resetHistory(); revision &+= 1 }

    private func push(_ c: Change) {
        undoStack.append(c); if undoStack.count > Self.depth { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func apply(_ items: [Change.Item], forward: Bool) {
        guard !items.isEmpty else { return }
        var kept = keptCount, out = outCount
        func count(_ i: Change.Item) -> Bool? {
            let from = forward ? i.before : i.after, to = forward ? i.after : i.before
            if from == true { kept -= 1 } else if from == false { out -= 1 }
            if to == true { kept += 1 } else if to == false { out += 1 }
            return to
        }
        if items.count == 1 {
            keep[items[0].id] = count(items[0])
        } else {
            // A step over several photos lands as one assignment: nobody sees it half applied.
            var next = keep
            for i in items { next[i.id] = count(i) }
            keep = next
        }
        keptCount = kept; outCount = out
        revision &+= 1
    }
}
