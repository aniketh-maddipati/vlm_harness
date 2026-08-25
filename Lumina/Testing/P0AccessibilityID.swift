import Foundation

/// Canonical, stable accessibility identifiers for every user-actionable or test-observable P0
/// element. The XCUITest target holds a string-for-string mirror of this namespace
/// (`LuminaUITests/Support/P0AXID.swift`) because a black-box UI-test bundle cannot import the app
/// module. `docs/P0_UI_AUTOMATION.md` documents the contract; the mirror must stay in sync.
///
/// Rules:
/// - Identifiers are stable and semantic — never derived from a cell's current array index.
/// - Per-asset elements are keyed by the asset's durable UUID via `assetCell(_:)`.
/// - Adding identifiers must not change any visual appearance.
/// - **Never attach a container-level identifier to a SwiftUI view that has identified children:**
///   SwiftUI propagates a container's `accessibilityIdentifier` onto every descendant, clobbering
///   their specific identifiers. Container constants below (`contactSheet`, `openView`,
///   `singlePhoto`, `toolbar`, `filmstrip`) are therefore *not* attached to containers — the
///   harness detects surfaces via the state probe's `route` and detects the filmstrip via its
///   items. They remain here for the probe/mirror documentation contract.
enum P0AccessibilityID {
    // Open surface
    static let openView = "p0.open"
    static let openChooseFolder = "p0.open.chooseFolder"
    static let recentShootPrefix = "p0.open.recent."      // + shoot name
    static func recentShoot(_ name: String) -> String { recentShootPrefix + name }

    // Contact sheet
    static let contactSheet = "p0.contactSheet"
    static let contactCollection = "p0.contactSheet.collection"
    static let chapterMarkPrefix = "p0.chapter."
    static func chapterMark(_ id: String) -> String { chapterMarkPrefix + id }
    static let keptRail = "p0.keptRail"
    static let contactCellPrefix = "p0.asset."            // + asset UUID
    static func assetCell(_ id: UUID) -> String { contactCellPrefix + id.uuidString }
    /// D47 / A3 — persistent pointer cull targets on the focused frame only.
    static let pointerCullKeep = "p0.pointerCull.keep"
    static let pointerCullReject = "p0.pointerCull.reject"

    // Toolbar / counts / controls
    static let toolbar = "p0.toolbar"
    static let homeButton = "p0.toolbar.home"             // back to Open surface
    static let shootTitle = "p0.toolbar.title"
    static let preparationStatus = "p0.toolbar.preparation"
    static let selectionCount = "p0.selectionCount"
    // Kept count is authoritatively read from the state probe JSON (`keptCount`). The toolbar shows
    // it as the derived "export" chip (exportCount == keptCount); this constant is kept for mirror
    // parity and probe-key documentation.
    static let keptCount = "p0.keptCount"
    static let exportCount = "p0.exportCount"
    static let undoButton = "p0.undo"
    static let gridReturn = "p0.gridReturn"
    static let densityIncrease = "p0.density.increase"     // fewer photographs (bigger cells)
    static let densityDecrease = "p0.density.decrease"     // more photographs (smaller cells)
    static let densityValue = "p0.density.value"

    // Single-photo surface
    static let singlePhoto = "p0.singlePhoto"
    static let singlePhotoImage = "p0.singlePhoto.image"
    static let singlePhotoFilename = "p0.singlePhoto.filename"
    static let singlePhotoCullChip = "p0.singlePhoto.cullChip"
    static let singlePhotoUnavailable = "p0.singlePhoto.unavailable"
    static let singlePhotoOriginalOffline = "p0.singlePhoto.originalOffline"
    static let filmstrip = "p0.filmstrip"
    static let filmstripItemPrefix = "p0.filmstrip."       // + asset UUID
    static func filmstripItem(_ id: UUID) -> String { filmstripItemPrefix + id.uuidString }
    // One representative adjustment control, so the harness can drive a real edit gesture.
    static let singlePhotoExposureSlider = "p0.singlePhoto.exposure"

    // Structured state probe — the authoritative machine-readable snapshot of session state.
    // Its accessibilityValue is a JSON document (see UITestStateProbe / ProbeSnapshot).
    static let stateProbe = "p0.stateProbe"
}
