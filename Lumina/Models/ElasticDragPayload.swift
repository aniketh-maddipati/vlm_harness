import Foundation

/// What a dragged frame carries: the ids of the frames moving, as one plain string
/// (`text/plain`, comma-separated — the prototype's `dataTransfer`). A dragged frame
/// that is part of the selection brings the whole selection with it.
nonisolated enum ElasticDragPayload {
    static let separator = ","

    static func encode(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).joined(separator: separator)
    }

    /// Ids in order, unknown or malformed pieces dropped, duplicates removed.
    static func decode(_ payload: String) -> [UUID] {
        var seen: Set<UUID> = []
        return payload
            .split(separator: Character(separator))
            .compactMap { UUID(uuidString: String($0)) }
            .filter { seen.insert($0).inserted }
    }

    /// The selection when the dragged frame is in it; otherwise just the frame.
    static func ids(forDragging id: UUID, selection: [UUID]) -> [UUID] {
        selection.contains(id) ? selection : [id]
    }
}
