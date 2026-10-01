import Foundation

// WP-6. The words of Help and the first-run intro. Kept in Core so the tests can hold them to
// KEYMAP.md (R-26: no T, and R is only a turn inside Crop).

public struct HelpGroup: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var keys: String, text: String
        public init(_ keys: String, _ text: String) { self.keys = keys; self.text = text }
    }
    public var title: String
    public var rows: [Row]
    public init(_ title: String, _ rows: [Row]) { self.title = title; self.rows = rows }
}

public enum HelpContent {
    /// Five groups: the prototype's, with every key of KEYMAP.md's Edit and trackpad tables.
    public static let groups: [HelpGroup] = [
        HelpGroup("Essentials", [
            .init("⏎", "next photo · on the last, go to Save"),
            .init("⌘Z · ⇧⌘Z", "undo · redo"),
            .init("\\ hold", "see the original · a tap switches it"),
            .init("C", "crop and straighten"),
            .init("V hold", "variations of the setting under the pointer · let go to apply · a tap opens them"),
            .init("?", "all keys"),
        ]),
        HelpGroup("Move", [
            .init("← →", "previous / next photo"),
            .init("↑ ↓", "previous / next scene"),
            .init("⌘1 – ⌘4", "Open · Cull · Edit · Save"),
            .init("⌘S", "go to Save"),
        ]),
        HelpGroup("Edit", [
            .init("drag", "a setting · ⇧ fine · ⌥ finer · esc cancels"),
            .init("dbl-click", "reset it · click the number to type"),
            .init("A", "Auto · again undoes"),
            .init(", .", "nudge the setting under the pointer · ⇧ ×5"),
            .init("[ ]", "choose the setting to nudge"),
            .init("0 · ⇧0", "reset it · reset all"),
            .init("=", "same as the last photo"),
            .init("W", "pick white: click something neutral grey"),
            .init("X", "out · ⌘Z brings it back"),
            .init("⌘C · ⌘V", "copy / paste settings"),
        ]),
        HelpGroup("Look", [
            .init("S", "straighten: draw along a horizon"),
            .init("C, then R", "turn 90° (in Crop) · ⇧R turns left"),
            .init("Z · click", "1:1 at the pointer · again fits · drag to look around"),
            .init("⌘+ ⌘− ⌘0", "zoom in / out (smaller than fit too) / fit"),
            .init("H", "focus: only the photo · again or esc returns"),
            .init("esc", "back out one layer: focus, zoom, before, scene grid, picker"),
            .init("⌥ drag ↕", "with Colour open: the colour under the pointer"),
        ]),
        HelpGroup("Trackpad", [
            .init("2-finger ↔", "on the photo: next / previous"),
            .init("pinch", "on the photo: zoom"),
            .init("force click", "before while held"),
            .init("2-finger ↔", "on a setting: adjust it"),
        ]),
    ]
    public static let introAgain = "Show the intro again"
}

public struct IntroCard: Equatable, Sendable {
    public var number: String, title: String, text: String, key: String
}

public enum IntroContent {
    public static let title = "Editing in Lumina"
    public static let subtitle = "Three things worth knowing. Everything can be undone."
    /// README: three numbered cards (the prototype had five; these are its 1, 2 and 4).
    public static let cards: [IntroCard] = [
        IntroCard(number: "1", title: "Drag any slider", text: "Hold ⇧ for fine control. Double-click resets it. Click the number to type a value.", key: "⇧"),
        IntroCard(number: "2", title: "Before and Variations", text: "Hold \\ to see the original. Hold V for a quick darker / brighter check; point at one and let go to apply it.", key: "V"),
        IntroCard(number: "3", title: "⏎ moves you on", text: "Edits save as you go. ⏎ opens the next photo; on the last one it takes you to Save. X takes a photo out.", key: "⏎"),
    ]
    public static let allShortcuts = "All shortcuts"
    public static let start = "Start editing"
}

/// Messages the overlays put in the toast.
public enum OverlayCopy {
    public static let variationsTap = "Variations · click one, or arrows then ⏎ · V or esc closes"
    public static let variationsClosed = "Closed. Nothing changed."
    public static let variationsKept = "Kept as it was."
    public static let variationsNoPhoto = "This photo didn’t load. Retry first."
    public static let variationsHeldHint = "point or ← → · let go of V to apply"
    public static let variationsStickyHint = "click one, or ← → then ⏎"
    public static let whiteBalanceHint = "← → temperature · ↑ ↓ tint"
    public static let pickerOff = "Picker off"
    public static let pickerTitle = "Pick white"
    public static let pickerHint = "click something neutral · esc / click here cancels"
    public static let straightenCancelled = "Straighten cancelled."
    public static let sceneGridHint = "click a photo to open it"
    /// How long a toast stays (prototype: 3.5 s).
    public static let toastSeconds: TimeInterval = 3.5
}
