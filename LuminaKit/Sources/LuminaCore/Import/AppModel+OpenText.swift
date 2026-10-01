import Foundation

// WP-2. The words on Open (README §1; the prototype where the README is silent). They live here,
// next to the state they describe, so the headless tests read exactly what the screen shows.

public extension AppModel {
    internal var openUndecided: Int { max(0, (shoot.local ? total : copied) - decisions.keptCount - decisions.outCount) }

    /// "SD card · Untitled".
    var openCardName: String { "SD card · \((shoot.local ? openFeature.cardShoot?.name : shoot.name) ?? "Untitled")" }

    /// "{camera} · {N} photos · {S} scenes · {first}–{last}"; a part the shoot doesn't have is left out.
    var openCardDetails: String {
        [shoot.label, "\(Self.grouped(total)) photos", "\(shoot.scenes.count) scenes", shoot.span].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The card button's three labels.
    var openCardButton: String {
        if copied >= total { return "Continue culling" }
        return copying || copied > 0 ? "Copying… start culling" : "Copy & start culling"
    }

    /// The gold bar under the card button: how much of the card has been copied (nil before any).
    var openCopyFraction: Double? { copied > 0 && total > 0 ? min(1, Double(copied) / Double(total)) : nil }

    /// "Checking 24 of 400 files…" while an import is being checked.
    var openImportProgress: String? {
        imports.busy ? "Checking \(Self.grouped(imports.checked)) of \(Self.grouped(imports.toCheck)) files…" : nil
    }
    var openImportFraction: Double { imports.toCheck > 0 ? min(1, Double(imports.checked) / Double(imports.toCheck)) : 0 }

    /// The result of the last import, once nothing is being checked.
    var openImportMessage: String? { imports.busy ? nil : imports.message }

    /// Recent shows once something has been opened: copied from the card, or imported.
    var openShowsRecent: Bool { !shoot.isEmpty && copied > 0 }
    var openRecentTitle: String { "Today · \(shoot.name)" }
    var openRecentDetails: String {
        var parts = ["\(Self.grouped(total)) photos", "\(Self.grouped(decisions.keptCount + decisions.outCount)) decided"]
        let edited = edits.looks.isEmpty ? 0 : keptIDs.filter { edits.isEdited($0, decisions: decisions) }.count
        if edited > 0 { parts.append("\(Self.grouped(edited)) edited") }
        return parts.joined(separator: " · ")
    }
    /// What the Recent row does next: "Saved 14:02", "Resume culling" or "Ready to save".
    var openRecentAction: String {
        if let s = save.saved { return "Saved \(SceneGrouper.clock(s.at).prefix(5))" }
        return openUndecided > 0 || decisions.keptCount == 0 ? "Resume culling" : "Ready to save"
    }

    /// "Start over", then for 4 s "Click again to clear {n} decisions" (R-31).
    var openStartOverTitle: String {
        guard open.startOverArmedUntil != nil else { return "Start over" }
        let n = decisions.keptCount + decisions.outCount
        return "Click again to clear \(Self.grouped(n)) decisions"
    }

    /// The folder row: an imported folder that is not on screen (after a relaunch, or behind the card).
    var openShowsReopen: Bool { !shoot.local && open.reopenName != nil }
    var openReopenTitle: String { "Folder · \(open.reopenName ?? "")" }
    var openReopenDetails: String { "\(Self.grouped(open.reopenCount)) photos · choose the folder again to see them. Your decisions are kept." }

    /// 1000 → "1,000", the same on every Mac.
    internal static func grouped(_ n: Int) -> String {
        var s = String(abs(n)), out = ""
        while s.count > 3 { out = "," + s.suffix(3) + out; s.removeLast(3) }
        return (n < 0 ? "-" : "") + s + out
    }
}
