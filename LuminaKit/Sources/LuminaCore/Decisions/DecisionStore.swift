import Foundation
import Observation

// WP-3. Keep / Out decisions with exact undo and redo, 200 deep (R-04, R-05).

@Observable
public final class DecisionStore: @unchecked Sendable {
    /// One undo step: one or more photos changed together (Keep suggested is one step).
    public struct Change: Equatable, Sendable {
        public var items: [Item]
        /// Cull's current photo when the decision was made; undo puts it back (parity traces).
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
        undoStack.append(Change(items: items, cur: cur)); if undoStack.count > Self.depth { undoStack.removeFirst() }
        redoStack.removeAll()
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
    public func resetHistory() { undoStack.removeAll(); redoStack.removeAll() }
    public func clear() { keep = [:]; keptCount = 0; outCount = 0; resetHistory(); revision &+= 1 }

    private func apply(_ items: [Change.Item], forward: Bool) {
        for i in items {
            let from = forward ? i.before : i.after, to = forward ? i.after : i.before
            if from == true { keptCount -= 1 } else if from == false { outCount -= 1 }
            if to == true { keptCount += 1 } else if to == false { outCount += 1 }
            keep[i.id] = to
        }
        revision &+= 1
    }
}
