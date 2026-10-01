import Foundation

// WP-7. Every word the Save screen shows (README §4; the prototype for the wording the README
// leaves out), worked out from the model in one place so the headless tests can read it.

public struct SavePresentation: Equatable, Sendable {
    public static let title = "Save"
    public static let subtitle = "Originals are never changed. You can save again any time."
    public static let saveFor = "Save for"
    public static let includeEdits = "Include my edits"
    public static func formatLabel(_ f: SaveFormat) -> String { switch f { case .xmp: "Lightroom"; case .folder: "Folder"; case .jpeg: "JPEG" } }

    /// "{n} keepers ready to save" / "No keepers yet".
    public var summary: String
    /// "{x} out · {y} undecided · not saved"; empty when everything is kept.
    public var behind: String
    /// Something is undecided: the "Finish culling" link shows.
    public var hasUndecided: Bool
    public var description: String
    /// The destination line, home folder as "~".
    public var destination: String
    /// "Change…" applies (sidecars always go next to each photo).
    public var canChangeDestination: Bool
    /// Something kept is edited: the "Include my edits" row shows.
    public var showsIncludeEdits: Bool
    public var editsSubline: String
    public var buttonLabel: String
    public var buttonEnabled: Bool
    public var note: String
    public var noteIsError: Bool
    /// Nil until something has been saved.
    public var savedTitle: String?
    public var savedHint: String?
}

public extension AppModel {
    var savePresentation: SavePresentation {
        let n = keptIDs.count, out = decisions.outCount, undecided = max(0, total - decisions.keptCount - out)
        let edited = keptEditedCount, withEdits = save.withEdits && edited > 0, current = saveIsCurrent, sv = save.saved
        let photos = { (k: Int) in "\(k) photo\(k == 1 ? "" : "s")" }

        var behind = [out > 0 ? "\(out) out" : nil, undecided > 0 ? "\(undecided) undecided" : nil].compactMap { $0 }.joined(separator: " · ")
        if !behind.isEmpty { behind += " · not saved" }

        let description: String, destination: String
        switch save.fmt {
        case .xmp:
            description = "A small .xmp file next to each RAW: keepers as 3★\(withEdits ? ", edits as develop settings" : ""). The RAW is untouched. Works with Capture One too."
            destination = "next to the RAWs in " + Self.tilde(shootFolder)
        case .folder:
            description = "Copies of your keepers\(withEdits ? ", with an .xmp for edited ones" : ""). Nothing else."
            destination = Self.tilde(exportDestination(.folder))
        case .jpeg:
            description = "Full-size sRGB JPEGs. " + (withEdits ? "Edits baked in; the rest as shot." : "All as shot.")
            destination = Self.tilde(exportDestination(.jpeg))
        }

        let note: String
        if let m = save.message { note = m }
        else if n == 0 { note = "Keep photos in Cull first." }
        else if current { note = "Up to date." }
        else if let sv { note = "Changed since \(Self.hhmm(sv.at)). Only what changed is rewritten." }
        else { note = "" }

        return SavePresentation(
            summary: n == 0 ? "No keepers yet" : "\(n) keeper\(n == 1 ? "" : "s") ready to save",
            behind: behind, hasUndecided: undecided > 0, description: description, destination: destination,
            canChangeDestination: save.fmt != .xmp,
            showsIncludeEdits: edited > 0,
            editsSubline: save.withEdits ? "\(edited) edited, \(n - edited) as shot" : "All as shot · edits stay in Lumina",
            buttonLabel: n == 0 ? "Nothing to save yet" : current ? "✓ Saved" : sv != nil ? "Save again · \(photos(n))" : "Save \(photos(n))",
            buttonEnabled: n > 0 && !current,
            note: note, noteIsError: save.message != nil && saveFeature.messageIsError,
            savedTitle: sv.map { "\($0.again ? "Saved again" : "Saved") · \(photos($0.n))\($0.ne > 0 ? ", \($0.ne) with edits" : ", as shot") · \(Self.hhmm($0.at))" },
            savedHint: sv.map { switch $0.fmt {
                case .xmp: "In Lightroom: Import → Add, or Metadata → Read Metadata from Files."
                case .jpeg: "JPEGs are ready to share or upload."
                case .folder: "Copies are checked against the originals."
            } })
    }

    /// "hh:mm" on the user's clock.
    static func hhmm(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// A path with the home folder as "~".
    static func tilde(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path, p = url.path
        return p == home ? "~" : p.hasPrefix(home + "/") ? "~" + p.dropFirst(home.count) : p
    }
}
