import SwiftUI

// WP-0 contract: every identifier in ACCESSIBILITY_CONTRACT.md. The XCTests find views by these.

public enum AccessibilityID {
    public static func step(_ s: String) -> String { "step.\(s)" }
    public enum Shell { public static let copyStatus = "shell.copyStatus", dropOverlay = "shell.dropOverlay" }
    public enum Open {
        public static let card = "open.card", openFolder = "open.openFolder", choosePhotos = "open.choosePhotos"
        public static let importProgress = "open.importProgress", importMessage = "open.importMessage"
        public static let recent = "open.recent", startOver = "open.startOver", reopenFolder = "open.reopenFolder"
    }
    public enum Cull {
        public static let grid = "cull.grid", preview = "cull.preview", previewMeta = "cull.previewMeta", previewState = "cull.previewState"
        public static let keep = "cull.keep", out = "cull.out", decided = "cull.decided"
        public static let toEdit = "cull.toEdit", toSave = "cull.toSave", message = "cull.message"
        public static func scene(_ i: Int) -> String { "cull.scene.\(i)" }
        public static func keepSuggested(_ i: Int) -> String { "cull.keepSuggested.\(i)" }
        public static func tile(_ id: String) -> String { "cull.tile.\(id)" }
    }
    public enum Edit {
        public static let canvas = "edit.canvas", photo = "edit.photo", photoLowRes = "edit.photoLowRes"
        public static let empty = "edit.empty", emptyGoCull = "edit.empty.goCull", loadError = "edit.loadError", retry = "edit.retry"
        public static let valueField = "edit.valueField", variations = "edit.variations"
        public static let help = "edit.help", intro = "edit.intro", crop = "edit.crop", cropRatio = "edit.cropRatio", zoom = "edit.zoom"
        public static let prev = "edit.prev", next = "edit.next", save = "edit.save", out = "edit.out", undo = "edit.undo", redo = "edit.redo"
        public static let filmstrip = "edit.filmstrip", facts = "edit.facts", hint = "edit.hint", toast = "edit.toast", warning = "edit.warning"
        // The histogram, the Curve graph and the footer (prototype `data-lumina` histogram / curve / footer).
        public static let histogram = "edit.histogram", shadowsClipping = "edit.histogram.shadowsClipping", highlightsClipping = "edit.histogram.highlightsClipping"
        public static let curve = "edit.curve", curveReadout = "edit.curve.readout"
        public static let saveStatus = "edit.saveStatus", shortcuts = "edit.shortcuts"
        public static func curvePoint(_ key: String) -> String { "edit.curve.point.\(key)" }
        /// "Soft contrast" → `edit.curvePreset.softContrast`.
        public static func curvePreset(_ name: String) -> String {
            let words = name.split(separator: " ").map(String.init)
            let camel = words.enumerated().map { $0.offset == 0 ? $0.element.lowercased() : $0.element.prefix(1).uppercased() + $0.element.dropFirst().lowercased() }
            return "edit.curvePreset.\(camel.joined())"
        }
        public static func section(_ s: String) -> String { "edit.section.\(s)" }
        public static func slider(_ key: String) -> String { "edit.slider.\(key)" }
        public static func value(_ key: String) -> String { "edit.value.\(key)" }
        public static func tool(_ t: String) -> String { "edit.tool.\(t)" }
        public static func variation(_ i: Int) -> String { "edit.variation.\(i)" }
    }
    public enum Save {
        public static let includeEdits = "save.includeEdits", button = "save.button", note = "save.note", summary = "save.summary", savedCard = "save.savedCard"
        public static func format(_ f: String) -> String { "save.format.\(f)" }
    }
    public enum Debug { public static let state = "debug.state", metrics = "debug.metrics", memoryMB = "debug.memoryMB", command = "debug.command" }
}

public extension View {
    /// A status text the tests read: identifier + value = the full text.
    func luminaStatus(_ id: String, _ value: String) -> some View {
        accessibilityElement(children: .ignore).accessibilityIdentifier(id).accessibilityLabel(value).accessibilityValue(value)
    }
}
