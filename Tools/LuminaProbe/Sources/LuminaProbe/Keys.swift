import AppKit

/// Key names as the page sees them (`e.key` for named keys, the character otherwise) mapped to
/// macOS virtual key codes. WebKit derives `e.code` from the key code, so this must be the real
/// hardware code or `e.code === 'KeyX'` checks in the page will miss.
enum Keys {
    struct Stroke {
        let code: UInt16
        let chars: String          // characters with modifiers applied
        let bare: String           // charactersIgnoringModifiers
    }

    private static let letters: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
    private static let symbols: [Character: (UInt16, Character)] = [   // key → (code, shifted char)
        "1": (18, "!"), "2": (19, "@"), "3": (20, "#"), "4": (21, "$"), "5": (23, "%"), "6": (22, "^"),
        "7": (26, "&"), "8": (28, "*"), "9": (25, "("), "0": (29, ")"), "=": (24, "+"), "-": (27, "_"),
        "[": (33, "{"), "]": (30, "}"), ";": (41, ":"), "'": (39, "\""), ",": (43, "<"), ".": (47, ">"),
        "/": (44, "?"), "\\": (42, "|"), "`": (50, "~"),
    ]
    private static let named: [String: (UInt16, String)] = [
        "Enter": (36, "\r"), "Escape": (53, "\u{1b}"), "Tab": (48, "\t"), " ": (49, " "), "Space": (49, " "),
        "Backspace": (51, "\u{7f}"), "Delete": (117, String(UnicodeScalar(NSDeleteFunctionKey)!)),
        "ArrowLeft": (123, String(UnicodeScalar(NSLeftArrowFunctionKey)!)),
        "ArrowRight": (124, String(UnicodeScalar(NSRightArrowFunctionKey)!)),
        "ArrowDown": (125, String(UnicodeScalar(NSDownArrowFunctionKey)!)),
        "ArrowUp": (126, String(UnicodeScalar(NSUpArrowFunctionKey)!)),
        "Home": (115, String(UnicodeScalar(NSHomeFunctionKey)!)), "End": (119, String(UnicodeScalar(NSEndFunctionKey)!)),
        "PageUp": (116, String(UnicodeScalar(NSPageUpFunctionKey)!)), "PageDown": (121, String(UnicodeScalar(NSPageDownFunctionKey)!)),
    ]
    /// Shifted characters typed as-is ("?", "A") resolve to their base key + shift.
    private static let shiftedToBase: [Character: Character] = {
        var m: [Character: Character] = [:]
        for (k, v) in symbols { m[v.1] = k }
        return m
    }()

    /// Returns the stroke and whether shift is implied by the key name itself.
    static func stroke(_ key: String, shift: Bool) -> (Stroke, Bool)? {
        if let (code, ch) = named[key] { return (Stroke(code: code, chars: ch, bare: ch), false) }
        guard key.count == 1, let c = key.first else { return nil }
        if let code = letters[Character(c.lowercased())] {
            let upper = c.isUppercase
            let s = shift || upper
            return (Stroke(code: code, chars: s ? c.uppercased() : c.lowercased(), bare: c.lowercased()), upper)
        }
        if let (code, shifted) = symbols[c] {
            return (Stroke(code: code, chars: shift ? String(shifted) : String(c), bare: String(c)), false)
        }
        if let base = shiftedToBase[c], let (code, _) = symbols[base] {
            return (Stroke(code: code, chars: String(c), bare: String(base)), true)
        }
        return nil
    }

    /// Every key the v7 page handles (`onKey`, `openKey`, `cullKey`, `handKey` in `Lumina Sets v7.dc.html`),
    /// plus the letters it answers with a hint (U L G, digits in the large view), for the fuzzer.
    /// K P T keep, R X remove, F E B hold overlays (M too in the large view), Z holds 100 %, Q undoes in
    /// the large view, Y toggles the tray, H the key bar. Dead in v7 and so left out: C, O (only ⌘O is
    /// bound; the fuzzer never presses it, it opens a native panel) and `,` (only ⌘,). Modifiers
    /// (⌘ ⇧ ⌥) are added at random by the fuzz step.
    static let pageKeys: [String] = [
        "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Enter", "Escape", "Tab", " ", "Backspace",
        "1", "2", "3", "4", "5", "0", "=", "-", "?",
        "a", "b", "e", "f", "g", "h", "k", "l", "m", "p", "q", "r", "t", "u", "x", "y", "z",
    ]
    /// Keys the fuzz step may press with ⌘ (v7: ⌘1–4 steps, ⌘A keep row, ⌘R Finder, ⌘Z undo, ⇧⌘Z redo).
    /// Never ⌘O (native folder panel in app mode), ⌘⏎ (Save writes), ⌥⌘⌫ (clears decisions) or ⌘, (the
    /// pool has no `,`, as before).
    static let cmdKeys: [String] = ["z", "1", "2", "3", "4", "a", "r"]
    /// Keys the page reads on key down and key up (overlays F E B M, Z zoom, K P R T X decide on hold,
    /// Space large, arrows repeat): pressed as held sometimes.
    static let heldKeys: [String] = ["z", " ", "ArrowLeft", "ArrowRight", "f", "e", "b", "m", "k", "p", "r", "t", "x"]
}
