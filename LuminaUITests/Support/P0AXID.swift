import Foundation

/// String-for-string mirror of the app's `P0AccessibilityID`.
///
/// A black-box XCUITest bundle cannot import the app module, so the identifier contract is
/// duplicated here. **This must stay in sync with `Lumina/Testing/P0AccessibilityID.swift`.**
/// `docs/P0_UI_AUTOMATION.md` documents the contract; `LuminaLogicTests` additionally checks the
/// app side of the contract from inside the module.
enum P0AXID {
    // Open surface
    static let openView = "p0.open"
    static let openChooseFolder = "p0.open.chooseFolder"
    static let recentShootPrefix = "p0.open.recent."
    static func recentShoot(_ name: String) -> String { recentShootPrefix + name }

    // Contact sheet
    static let contactSheet = "p0.contactSheet"
    static let contactCollection = "p0.contactSheet.collection"
    static let contactCellPrefix = "p0.asset."
    static func assetCell(_ id: String) -> String { contactCellPrefix + id }

    // Toolbar / counts / controls
    static let toolbar = "p0.toolbar"
    static let homeButton = "p0.toolbar.home"
    static let shootTitle = "p0.toolbar.title"
    static let preparationStatus = "p0.toolbar.preparation"
    static let selectionCount = "p0.selectionCount"
    static let keptCount = "p0.keptCount"
    static let exportCount = "p0.exportCount"
    static let undoButton = "p0.undo"
    static let gridReturn = "p0.gridReturn"
    static let densityIncrease = "p0.density.increase"
    static let densityDecrease = "p0.density.decrease"
    static let densityValue = "p0.density.value"

    // Single-photo surface
    static let singlePhoto = "p0.singlePhoto"
    static let singlePhotoImage = "p0.singlePhoto.image"
    static let singlePhotoFilename = "p0.singlePhoto.filename"
    static let singlePhotoCullChip = "p0.singlePhoto.cullChip"
    static let singlePhotoUnavailable = "p0.singlePhoto.unavailable"
    static let singlePhotoOriginalOffline = "p0.singlePhoto.originalOffline"
    static let filmstrip = "p0.filmstrip"
    static let filmstripItemPrefix = "p0.filmstrip."
    static func filmstripItem(_ id: String) -> String { filmstripItemPrefix + id }
    static let singlePhotoExposureSlider = "p0.singlePhoto.exposure"

    // Structured state probe
    static let stateProbe = "p0.stateProbe"
}
