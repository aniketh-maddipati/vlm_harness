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
    /// Provenance of the focused asset's recipe (`RecipeSource`). Mirrors
    /// `Lumina/Testing/UITestStateProbe.swift`.
    var focusedRecipeSource: String?
    /// Progressive rendering state for stability assertions.
    var focusedRenderFidelity: String? = nil
    var focusedHasPresentedRAW: Bool? = nil
    var inspectionSettledLongEdge: Int? = nil
    var focusedOrientedIsPortrait: Bool? = nil
    var focusedPresentedIsPortrait: Bool? = nil
    /// D47/A3 — pointer cull mark targets visible on the focused contact-sheet frame.
    var pointerCullTargetsVisible: Bool
    var inspectingAssetID: String?
    /// Persistent selection membership. Pointer travel must not write this (Law 1 / D29).
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
    /// E2 — whether the display-link render instruments (`p0.scroll.frame`, `p0.key.travel`,
    /// `p0.key.mark`, `p0.zoom.gesture`) are live. Off in an ordinary run; a measurement
    /// session asserts this is true before it trusts a single number.
    var renderInstrumentsEnabled: Bool
    /// Law 5 / D11 — Esc would clear a transient hold before navigation (`P0EscLadder`).
    var escTransientHoldActive: Bool
    /// Temporary four-variant edit branch (session-only; never persisted).
    var editVariantsActive: Bool
    var editVariantAssetID: String?
    var focusedEditVariantIndex: Int?
    var editVariantCancellationCount: Int
    var preparedSessionCreated: Int? = nil
    var preparedSessionHits: Int? = nil
    var interactiveMaterializations: Int? = nil
    var graphRenders: Int? = nil
    var gpuUploads: Int? = nil
    var variantRenders: Int? = nil
    var metalPresents: Int? = nil
    var variantSourceReady: Bool? = nil
    var elasticStripTrackHeight: Int = 90
    var elasticStripNearLongEdge: Int = 210
    var elasticStripFarLongEdge: Int = 64
    var chapterTableMounted: Bool = false
    var inspectPeripheryDimOpacity: Double = 1

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
