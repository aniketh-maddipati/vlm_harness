import Foundation

/// Single ordered Esc ladder for the P0 live path (Law 5 / D11).
/// First matching step wins — Esc never means two things at one depth.
///
/// The prototype's own order, deepest transient first:
/// 1. **Peek** — a held or pinned ⇥ peek closes.
/// 2. **Drawer** — the develop drawer closes.
/// 3. **Selection** — a selection clears.
/// 4. **Route** — the focus route returns to the time table, same cursor.
///
/// Nothing else answers to Esc: an open burst folds by its badge, a held key
/// releases with the key, and the table itself has nowhere further out to go.
@MainActor
enum P0EscLadder {
    /// Returns true when Esc was consumed.
    static func handle(session: P0SessionModel) -> Bool {
        if session.peek != nil {
            session.closePeek()
            return true
        }

        if session.developDrawerOpen {
            session.developDrawerOpen = false
            return true
        }

        if !session.selectedAssetIDs.isEmpty {
            session.selectedAssetIDs = []
            return true
        }

        if session.route == .focus {
            session.closeInspection()
            return true
        }

        return false
    }

    /// What the probe reports: Esc has something to unwind before it would move.
    static func hasTransientDepth(session: P0SessionModel) -> Bool {
        session.peek != nil || session.developDrawerOpen || !session.selectedAssetIDs.isEmpty
    }
}
