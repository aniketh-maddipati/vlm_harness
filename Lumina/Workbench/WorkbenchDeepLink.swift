#if DEBUG
import Foundation

/// A workbench deep-link — the polish surface an operator wants to look at, named on the
/// command line so it is reachable without clicking through the product.
///
/// Pure value + pure parser: no file system, no defaults store, no SwiftUI. `WorkbenchLaunch`
/// resolves it against the fixture root; `WorkbenchBoot` applies it to the session.
///
/// DEBUG-only, and additionally inert unless `--workbench` is passed (or the LuminaPlayground
/// target, which defaults it on). The shipping app never parses these.
struct WorkbenchDeepLink: Equatable {
    /// Latency card under `FIXTURE_ROOT` to boot from.
    var card: String = WorkbenchDeepLink.defaultCard
    /// Contact-sheet row to scroll to (1-based, as the operator counts rows). `nil` = top.
    var row: Int?
    /// Whether the row's first photograph takes focus on boot.
    var focused: Bool = false
    /// Which surface to land on.
    var surface: Surface = .table

    static let defaultCard = "card-clean-500"

    enum Surface: String, CaseIterable, Equatable {
        /// The P0 contact sheet.
        case table
        /// Single-photo editing surface (`inspectingAssetID`).
        case frame
        /// Named by the W0 brief; **no referent in P0 today** — see `WorkbenchBoot`, which
        /// reports it as unresolved rather than inventing a surface.
        case loupe
    }

    // MARK: - Flags

    static let cardFlag = "--card"
    static let rowFlag = "--row"
    static let focusedFlag = "--focused"
    static let surfaceFlag = "--surface"

    /// Parses a deep-link out of raw launch arguments.
    ///
    /// Unknown values never throw and never crash the app: a bad `--surface` keeps the default
    /// and is reported through `unresolved`, in the D35 spirit — the surface keeps working and
    /// the broken thing wears a chip.
    static func parse(arguments: [String]) -> (link: WorkbenchDeepLink, unresolved: [String]) {
        var link = WorkbenchDeepLink()
        var unresolved: [String] = []

        if let value = flagValue(cardFlag, in: arguments) {
            if value.isEmpty || value.hasPrefix("-") {
                unresolved.append("\(cardFlag) needs a card name — kept \(link.card)")
            } else {
                link.card = value
            }
        }

        if let value = flagValue(rowFlag, in: arguments) {
            if let row = Int(value), row >= 1 {
                link.row = row
            } else {
                unresolved.append("\(rowFlag) \(value) is not a row number ≥ 1 — kept top of table")
            }
        }

        link.focused = arguments.contains(focusedFlag)

        if let value = flagValue(surfaceFlag, in: arguments) {
            if let surface = Surface(rawValue: value) {
                link.surface = surface
            } else {
                let known = Surface.allCases.map(\.rawValue).joined(separator: "|")
                unresolved.append("\(surfaceFlag) \(value) is not one of \(known) — kept table")
            }
        }

        return (link, unresolved)
    }

    /// Renders this deep-link back to the arguments that reproduce it, so a HARNESS.md recipe
    /// and a running app can be compared without guessing.
    var arguments: [String] {
        var out = [WorkbenchLaunch.flag, Self.cardFlag, card]
        if let row { out += [Self.rowFlag, String(row)] }
        if focused { out.append(Self.focusedFlag) }
        out += [Self.surfaceFlag, surface.rawValue]
        return out
    }

    /// Value following `flag`, or nil when absent / last.
    private static func flagValue(_ flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return "" }
        return arguments[next]
    }
}
#endif
