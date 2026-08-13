import Foundation
import XCTest

/// Test-side mirror of the app's `ProbeSnapshot`. Decodes the JSON published on the state-probe
/// accessibility element (`P0AXID.stateProbe`). This — not UI text — is the authoritative source
/// of structured session state for assertions and invariants.
struct ProbeSnapshot: Codable, Equatable {
    var route: String
    var shootName: String?
    var fixture: String?
    var seed: String
    var assetCount: Int
    var visibleCount: Int
    var selectionCount: Int
    var keptCount: Int
    var rejectedCount: Int
    var unreviewedCount: Int
    var editedCount: Int
    var densityColumns: Int
    var filter: String
    var canUndo: Bool
    var focusedAssetID: String?
    var focusedVisible: Bool
    var focusedAvailability: String?
    var focusedCull: String?
    /// Deterministic fingerprint of the focused asset's canonical `EditRecipe` (nil when nothing is
    /// focused). Mirrors `Lumina/Testing/UITestStateProbe.swift`.
    var focusedRecipeFingerprint: String?
    /// D47/A3 — pointer cull mark targets visible on the focused contact-sheet frame.
    var pointerCullTargetsVisible: Bool
    var inspectingAssetID: String?
    var selectedAssetIDs: [String]
    var missingOriginalCount: Int
    var previewReadyCount: Int
    var phaseDetail: String
    var scrollAnchor: Double
    var culls: [String: String]
    var editedIDs: [String]
    var visibleAssetIDs: [String]
    var missingAssetIDs: [String]
    /// D27 — whether live-path transform/shadow animations snap (accessibility or harness flag).
    var reduceMotionActive: Bool
    /// W5 — sole P0 keyboard routing owner (`P0KeyRoutingModifier`).
    var keyRoutingOwner: String
    /// True when the explicit legacy Workbench door is open (W8).
    var legacyShellActive: Bool

    /// Convenience: the Nth visible asset ID (nil when out of range).
    func visibleID(at index: Int) -> String? {
        guard index >= 0, index < visibleAssetIDs.count else { return nil }
        return visibleAssetIDs[index]
    }

    static func decode(_ json: String) -> ProbeSnapshot? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProbeSnapshot.self, from: data)
    }
}
