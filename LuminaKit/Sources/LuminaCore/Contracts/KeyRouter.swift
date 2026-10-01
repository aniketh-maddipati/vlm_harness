import Foundation

// WP-0 contract: KEYMAP.md as a table. The single source of truth for what a key means and which
// layer owns it. Views never interpret keys themselves; they call `AppModel.handle(_:)`.

public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = KeyModifiers(rawValue: 1), shift = KeyModifiers(rawValue: 2)
    public static let option = KeyModifiers(rawValue: 4), control = KeyModifiers(rawValue: 8)
}

public struct KeyEvent: Hashable, Sendable {
    public enum Phase: Sendable { case down, up }
    /// Lower-case character ("r", ",", "\\", "0") or a name: "return", "escape", "left", "right",
    /// "up", "down", "tab", "delete", "space", "home", "end", "pageup", "pagedown".
    public var key: String
    public var modifiers: KeyModifiers
    public var isRepeat: Bool
    public var phase: Phase
    public init(_ key: String, _ modifiers: KeyModifiers = [], isRepeat: Bool = false, phase: Phase = .down) {
        // "?" is ⇧/ and "+" is ⇧=: fold the shifted characters back so the table has one spelling.
        var k = key.count == 1 ? key.lowercased() : key, m = modifiers
        if k == "?" { k = "/"; m.insert(.shift) }
        if k == "+" { k = "="; m.remove(.shift) }
        if k == "\r" || k == "\n" { k = "return" }
        if k == "\u{1b}" { k = "escape" }
        self.key = k; self.modifiers = m; self.isRepeat = isRepeat; self.phase = phase
    }
}

/// KEYMAP.md "Layer order". The topmost open layer handles input first.
public enum Layer: Hashable, Sendable {
    case textField, help, intro, crop, variations, rotateHold, control, step(Step), global

    var priority: Int {
        switch self {
        case .textField: 0; case .help: 1; case .intro: 2; case .crop: 3; case .variations: 4
        case .rotateHold: 5; case .control: 6; case .step: 7; case .global: 8
        }
    }
    /// A layer that owns the keyboard swallows every unbound single key (R-20…R-26).
    var ownsKeyboard: Bool { switch self { case .textField, .help, .intro, .crop, .variations: true; default: false } }
}

public enum Action: Equatable, Sendable {
    // Global
    case goStep(Step), saveShortcut, openFolder
    // Open
    case openEnter
    // Cull
    case keep, out, cullMove(Int), cullScene(Int), nextUndecided, cullUndo, cullRedo, tileSize(Int)
    // Edit
    case editEnter, editMove(Int), editScene(Int), editUndo, editRedo
    case before(down: Bool), variations(down: Bool)
    case crop, straighten, auto, nudge(Int, coarse: Bool), pickSetting(Int), reset, resetAll
    case sameAsLast, pickWhite, editOut, copySettings, pasteSettings
    case zoomToggle, zoomStep(Int), zoomFit, focus, editEscape, help
    // Crop
    case rotate(Int), cropAngle(Double), cropGrow(Int), cropMove(dx: Int, dy: Int, coarse: Bool)
    case cropUndo, cropRedo, cropKeep, cropCancel
    // Variations
    case variationMove(dx: Int, dy: Int), variationApply, variationClose
    // Help, intro
    case helpClose, introClose
    // Save
    case saveEnter, save
    /// Does nothing, and says why (R-20, and the owning layers' "Cropping · ⏎ keeps it · esc cancels").
    case explain(String)
    /// The key belongs to the text field being typed in; the field handles it (R-22).
    case typing
    /// Bound to nothing, on purpose (T, R-21) or because no layer wants it.
    case none
}

public struct Route: Equatable, Sendable {
    public var handler: Layer
    public var action: Action
    public init(_ handler: Layer, _ action: Action) { self.handler = handler; self.action = action }
}

public enum KeyRouter {
    public static let rExplanation = "R keeps photos in Cull, so it does nothing here. To turn this photo: C, then R."
    public static let cropSwallow = "Cropping · ⏎ keeps it · esc cancels"
    public static let saveGuard = "Paused so ⏎ doesn’t save by accident. Click Save or press ⌘S."

    /// Which layer handles `key`, and what it does. `layers` is the set of open layers in any
    /// order; `.global` is always implied.
    public static func route(_ key: KeyEvent, layers: [Layer]) -> Route {
        let stack = Set(layers).union([.global]).sorted { $0.priority < $1.priority }
        for layer in stack {
            if let a = binding(key, layer) { return Route(layer, a) }
            if layer.ownsKeyboard {
                // ⌘1–4, ⌘S and ⌘O still reach Global from under an overlay; nothing else does.
                if let g = binding(key, .global), key.modifiers.contains(.command) { return Route(.global, g) }
                if layer == .textField { return Route(layer, .typing) }
                return Route(layer, key.phase == .down && layer == .crop ? .explain(cropSwallow) : .none)
            }
        }
        return Route(stack.last ?? .global, .none)
    }

    static func binding(_ e: KeyEvent, _ layer: Layer) -> Action? {
        let k = e.key, m = e.modifiers, cmd = m.contains(.command), shift = m.contains(.shift), opt = m.contains(.option)
        let plain = !cmd && !m.contains(.control)
        // Key-up only matters for the two hold keys.
        if e.phase == .up {
            guard layer == .step(.edit) || layer == .variations, plain else { return nil }
            if k == "\\" && layer == .step(.edit) { return .before(down: false) }
            if k == "v" { return .variations(down: false) }
            return nil
        }
        switch layer {
        case .global:
            guard cmd, !opt else { return nil }
            switch k {
            case "1": return e.isRepeat ? Action.none : .goStep(.open)
            case "2": return e.isRepeat ? Action.none : .goStep(.cull)
            case "3": return e.isRepeat ? Action.none : .goStep(.edit)
            case "4": return e.isRepeat ? Action.none : .goStep(.save)
            case "s": return e.isRepeat ? Action.none : .saveShortcut
            case "o": return e.isRepeat ? Action.none : .openFolder
            default: return nil
            }
        case .step(.open):
            return plain && k == "return" ? (e.isRepeat ? Action.none : .openEnter) : nil
        case .step(.cull):
            if cmd {
                switch k {
                case "z": return shift ? .cullRedo : .cullUndo
                case "y": return .cullRedo
                case "=": return .tileSize(1)
                case "-": return .tileSize(-1)
                default: return nil
                }
            }
            switch k {
            case "r": return e.isRepeat ? Action.none : .keep
            case "x": return e.isRepeat ? Action.none : .out
            case "left": return .cullMove(-1)
            case "right": return .cullMove(1)
            case "up": return .cullScene(-1)
            case "down": return .cullScene(1)
            case "u": return .nextUndecided
            default: return nil
            }
        case .step(.edit):
            if cmd {
                switch k {
                case "z": return shift ? .editRedo : .editUndo
                case "y": return .editRedo
                case "c": return .copySettings
                case "v": return .pasteSettings
                case "=": return .zoomStep(1)
                case "-": return .zoomStep(-1)
                case "0": return .zoomFit
                default: return nil
                }
            }
            switch k {
            case "return": return .editEnter
            case "left": return .editMove(-1)
            case "right": return .editMove(1)
            case "up": return .editScene(-1)
            case "down": return .editScene(1)
            case "\\": return e.isRepeat ? Action.none : .before(down: true)
            case "v": return e.isRepeat ? Action.none : .variations(down: true)
            case "c": return .crop
            case "s": return .straighten
            case "a": return e.isRepeat ? Action.none : .auto
            case ",": return .nudge(-1, coarse: shift)
            case ".": return .nudge(1, coarse: shift)
            case "<": return .nudge(-1, coarse: true)
            case ">": return .nudge(1, coarse: true)
            case "[": return .pickSetting(-1)
            case "]": return .pickSetting(1)
            case "0": return shift ? .resetAll : .reset
            case ")": return .resetAll
            case "=": return .sameAsLast
            case "w": return .pickWhite
            case "x": return e.isRepeat ? Action.none : .editOut
            case "z": return e.isRepeat ? Action.none : .zoomToggle
            case "h": return e.isRepeat ? Action.none : .focus
            case "escape": return .editEscape
            case "/": return shift ? .help : nil
            case "r": return .explain(rExplanation)
            case "t": return Action.none
            default: return nil
            }
        case .step(.save):
            return plain && k == "return" ? (e.isRepeat ? Action.none : .saveEnter) : nil
        case .crop:
            if cmd { return k == "z" ? (shift ? .cropRedo : .cropUndo) : nil }
            switch k {
            case "r": return .rotate(shift ? -1 : 1)
            case "s": return .straighten
            case "left": return opt ? .cropMove(dx: -1, dy: 0, coarse: shift) : .cropAngle(shift ? -1 : -0.1)
            case "right": return opt ? .cropMove(dx: 1, dy: 0, coarse: shift) : .cropAngle(shift ? 1 : 0.1)
            case "up": return opt ? .cropMove(dx: 0, dy: -1, coarse: shift) : .cropGrow(1)
            case "down": return opt ? .cropMove(dx: 0, dy: 1, coarse: shift) : .cropGrow(-1)
            case "q": return shift ? .cropRedo : .cropUndo
            case "return", "c": return .cropKeep
            case "escape": return .cropCancel
            default: return nil
            }
        case .variations:
            guard plain else { return nil }
            switch k {
            case "left": return .variationMove(dx: -1, dy: 0)
            case "right": return .variationMove(dx: 1, dy: 0)
            case "up": return .variationMove(dx: 0, dy: -1)
            case "down": return .variationMove(dx: 0, dy: 1)
            case "return": return .variationApply
            case "escape": return .variationClose
            // A fresh V press closes; the held key's repeats are swallowed.
            case "v": return e.isRepeat ? Action.none : .variationClose
            default: return nil
            }
        case .help:
            return k == "escape" || (k == "/" && shift) ? .helpClose : nil
        case .intro:
            return k == "escape" || k == "return" ? .introClose : nil
        case .textField, .rotateHold, .control:
            return nil
        }
    }
}
