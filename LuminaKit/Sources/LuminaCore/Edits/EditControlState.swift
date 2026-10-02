import Foundation
import Observation

// WP-5. What the controls column remembers that no other work package needs: the copied
// settings, the last edit made ("="), Auto's way back, the drag in progress and the pending write.
// Reached with `model.editControls`.

@Observable
public final class EditControlState {
    /// ⌘C: the copied settings (never the crop).
    public var clipboard: Look?
    /// The last edit made on any photo; "=" repeats it.
    public var lastLook: Look?
    /// Auto, until something else changes the photo: pressing A again goes back to `before`.
    public struct AutoUndo: Equatable { public var key: String; public var before: Look; public var applied: Look }
    public var autoUndo: AutoUndo?

    /// A slider drag: where it started, where the thumb is on the track, whether it has moved the
    /// value yet, and whether it sits on the default's snap.
    public struct Drag: Equatable {
        public var key: String, photo: String
        public var start: Double
        public var position: Double
        public var snapped: Bool
        /// What "=" would have repeated before the drag (Esc puts it back).
        public var lastBefore: Look?
    }
    public var drag: Drag?
    /// [ ] or , . was used: the chosen row is marked until the pointer takes over.
    public var keyboardChoosing = false

    /// A two-finger swipe over a slider: what has built up since the last step.
    @ObservationIgnored var swipe: (key: String, sum: Double, at: Date, first: Bool)?
    /// Edits made during a drag that haven't been announced with `changed()` yet (R-07).
    @ObservationIgnored var dirty = false
    @ObservationIgnored var pendingWrite: ScheduledWork?

    /// The footer says "Saving…": a change was made in the last 0.7 s or is still being written.
    public internal(set) var saving = false
    @ObservationIgnored var savingClear: ScheduledWork?
    /// The last histogram measured for the Edit photo (nil until the provider has measured one).
    public internal(set) var histogram: EditHistogram?
    /// What the hint line says for something that isn't a slider (the clipping markers).
    public internal(set) var hintNote: String?

    public init() {}
}
