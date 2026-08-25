import Foundation

/// Single ordered Esc ladder for the P0 live path (Law 5 / D11).
/// First matching step wins — Esc never means two things at one depth.
///
/// Ordered rules (deepest transient state first):
/// 1. Grouping surface → return to contact sheet.
/// 2. Single-photo inspection → close and restore scroll/focus.
/// 3. *(reserved)* Active edit/crop drag → restore gesture baseline without navigation.
/// 4. *(reserved)* Latched crop → dismiss, revert entry layout.
/// 5. *(reserved)* Staged propagation → narrow one ring; at row ring cancel whole stage.
/// 6. *(reserved)* Un-applied staged batches → dissolve on relaunch.
///
/// Steps 3–6 mirror `LuminaShellModel.handleEscape` and land when P0 gains parity.
enum P0EscLadder {
    /// Returns true when Esc was consumed.
    static func handle(session: P0SessionModel) -> Bool {
        if session.holdingLoupe || session.holdingClipping {
            session.setHoldingLoupe(false)
            session.setHoldingClipping(false)
            return true
        }

        if session.lookGlancing {
            session.endLookGlance()
            return true
        }

        if session.leanedBurstID != nil {
            session.leaveBurstLean()
            return true
        }

        if session.walkingKeptRail {
            session.walkingKeptRail = false
            return true
        }

        if session.route == .grouping {
            session.leaveGrouping()
            return true
        }

        if session.inspectingAssetID != nil {
            session.closeInspection()
            return true
        }

        return false
    }
}
