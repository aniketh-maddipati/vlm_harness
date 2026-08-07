import Foundation
import XCTest

/// P0 invariants checked after actions. Each returns human-readable violations (empty = healthy).
/// Stateless checks read a single snapshot; cross-snapshot checks (undo, edit-unaffected) take a
/// before/after pair. UI text is never the source of truth — the structured probe is.
enum Invariants {
    /// Checks derivable from one snapshot plus live app presence.
    static func stateless(_ s: ProbeSnapshot, app: XCUIApplication) -> [String] {
        var violations: [String] = []

        if !app.windows.firstMatch.exists {
            violations.append("no visible main window")
        }
        guard ["open", "contactSheet", "singlePhoto"].contains(s.route) else {
            return violations + ["unidentifiable surface: \(s.route)"]
        }
        if app.alerts.firstMatch.exists {
            violations.append("unexpected alert present")
        }

        if s.route != "open" {
            if s.assetCount == 0 {
                violations.append("blank primary surface: 0 assets on \(s.route)")
            }
            if let focus = s.focusedAssetID, !s.focusedVisible, s.filter == "All" {
                violations.append("focus \(focus) not among visible assets (filter=All)")
            }
        }

        if s.selectionCount < 0 || s.selectionCount > s.assetCount {
            violations.append("selection count out of range: \(s.selectionCount)/\(s.assetCount)")
        }
        if s.selectionCount != s.selectedAssetIDs.count {
            violations.append("selection count \(s.selectionCount) != selected id list \(s.selectedAssetIDs.count)")
        }

        let keepFromMap = s.culls.values.filter { $0 == "keep" }.count
        if keepFromMap != s.keptCount {
            violations.append("kept count \(s.keptCount) != kept assets \(keepFromMap)")
        }
        let rejectFromMap = s.culls.values.filter { $0 == "reject" }.count
        if rejectFromMap != s.rejectedCount {
            violations.append("rejected count \(s.rejectedCount) != rejected assets \(rejectFromMap)")
        }
        if s.culls.count != s.assetCount {
            violations.append("cull map size \(s.culls.count) != asset count \(s.assetCount)")
        }
        let tallied = s.keptCount + s.rejectedCount + s.unreviewedCount
        if tallied != s.assetCount {
            violations.append("keep+reject+unreviewed (\(tallied)) != assetCount \(s.assetCount)")
        }
        return violations
    }

    /// Culling must never mutate edit markers.
    static func editMarkersUnchanged(before: ProbeSnapshot, after: ProbeSnapshot) -> [String] {
        before.editedIDs == after.editedIDs
            ? []
            : ["edit markers changed by a cull action: \(before.editedIDs) -> \(after.editedIDs)"]
    }

    /// Culling never removes assets from the catalog (rejected stay present).
    static func catalogPreserved(before: ProbeSnapshot, after: ProbeSnapshot) -> [String] {
        before.assetCount == after.assetCount
            ? []
            : ["asset count changed unexpectedly: \(before.assetCount) -> \(after.assetCount)"]
    }

    /// Undo must restore the exact prior cull map.
    static func undoRestored(previous: ProbeSnapshot, afterUndo: ProbeSnapshot) -> [String] {
        previous.culls == afterUndo.culls
            ? []
            : ["undo did not restore prior cull state"]
    }

    /// Assert stateless invariants, failing the test with the joined violations.
    static func assert(_ s: ProbeSnapshot, app: XCUIApplication, file: StaticString = #file, line: UInt = #line) {
        let violations = stateless(s, app: app)
        if !violations.isEmpty {
            XCTFail("invariant violations:\n- " + violations.joined(separator: "\n- "), file: file, line: line)
        }
    }
}
