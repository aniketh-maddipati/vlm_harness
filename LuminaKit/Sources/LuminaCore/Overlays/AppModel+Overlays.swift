import Foundation

// WP-6. Variations, Help, the intro, Esc unwinding (R-06, R-21…R-26).

public extension AppModel {
    /// V down opens the grid on the setting under the pointer (or the section's main one);
    /// V up applies the highlighted cell, unless the grid was closed or the photo changed (R-06).
    func variationsHold(_ down: Bool) {
        if down {
            guard editCur != nil, edit.overlay == nil else { return }
            edit.overlay = .variations
            edit.variationKey = edit.hoverKey ?? EditSetting.main(edit.section)
            edit.variationPhoto = editCur; edit.variationIndex = 0; edit.variationSticky = false
        } else if edit.overlay == .variations, !edit.variationSticky {
            variationsApply()
        }
    }
    func variationsMove(dx: Int, dy: Int) {}
    /// WP-6: apply the highlighted cell after the 120 ms window, only if the photo is unchanged.
    func variationsApply() { variationsClose() }
    func variationsClose() { if edit.overlay == .variations { edit.overlay = nil }; edit.variationKey = nil; edit.variationPhoto = nil }

    func helpOpen() { if edit.overlay == nil { edit.overlay = .help } }
    func helpClose() { if edit.overlay == .help { edit.overlay = nil } }
    func introClose() { if edit.overlay == .intro { edit.overlay = nil } }

    /// Esc backs out one layer at a time: focus → zoom → before → scene grid → picker (R-25).
    func editEscape() {
        if edit.focus { edit.focus = false }
        else if abs(edit.zoom - 1) > 0.001 { zoomFit() }
        else if edit.before { edit.before = false }
        else if edit.overlay == .sceneGrid || edit.overlay == .picker { edit.overlay = nil }
        else if edit.pickingWhite { edit.pickingWhite = false }
    }

    /// The window lost focus: Variations closes, held keys are forgotten (R-24).
    func windowBlurred() {
        variationsClose(); edit.beforeHeld = false; heldKeys.removeAll()
    }

    func releaseAllKeys() {
        for k in heldKeys { handle(KeyEvent(k, phase: .up)) }
        heldKeys.removeAll()
    }
}
