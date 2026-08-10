import CoreGraphics
import Foundation

/// Working crop geometry beneath a fixed on-screen boundary (hi-fi frame C).
struct CropLayoutState: Equatable, Sendable {
    var crop: EditCrop
    var straightenDegrees: Double
    /// Normalized pan of the photograph beneath the fixed boundary (−1…1).
    var photoPanX: Double
    var photoPanY: Double
    var orientationFlipped: Bool
    var aspectUnlocked: Bool

    static func from(recipe: EditRecipe) -> CropLayoutState {
        CropLayoutState(
            crop: recipe.crop?.normalized() ?? .full,
            straightenDegrees: recipe.straightenDegrees,
            photoPanX: 0,
            photoPanY: 0,
            orientationFlipped: false,
            aspectUnlocked: false
        )
    }

    /// Crop rect after pan / orientation — used for preview and sidecar write.
    var effectiveCrop: EditCrop {
        var c = crop.normalized()
        let panScale = 0.25
        c.x = min(max(c.x - photoPanX * panScale * c.width, 0), 1 - c.width)
        c.y = min(max(c.y - photoPanY * panScale * c.height, 0), 1 - c.height)
        if orientationFlipped {
            let cx = c.x + c.width / 2
            let cy = c.y + c.height / 2
            let nw = c.height
            let nh = c.width
            c = EditCrop(x: cx - nw / 2, y: cy - nh / 2, width: nw, height: nh).normalized()
        }
        return c
    }

    func merged(into recipe: EditRecipe) -> EditRecipe {
        recipe.updating {
            $0.crop = effectiveCrop
            $0.straightenDegrees = straightenDegrees
        }
    }

    /// Deterministic layout fingerprint for Esc/⏎ restoration tests.
    var layoutHash: String {
        let c = crop.normalized()
        return [
            c.fingerprint,
            String(format: "%.1f", straightenDegrees),
            String(format: "%.4f,%.4f", photoPanX, photoPanY),
            orientationFlipped ? "flip" : "norm",
            aspectUnlocked ? "free" : "lock",
        ].joined(separator: "|")
    }
}

/// Latched crop mode — boundary is the banner; Esc dismisses, ⏎ applies.
struct CropSession: Equatable, Sendable {
    var photoID: AssetID
    var baseline: CropLayoutState
    var working: CropLayoutState
    var isDraggingOutside: Bool = false

    var isActive: Bool { true }

    init(photoID: AssetID, recipe: EditRecipe) {
        self.photoID = photoID
        let state = CropLayoutState.from(recipe: recipe)
        baseline = state
        working = state
    }

    mutating func revert() {
        working = baseline
        isDraggingOutside = false
    }

    mutating func toggleAspectLock() {
        working.aspectUnlocked.toggle()
    }

    mutating func flipOrientation() {
        working.orientationFlipped.toggle()
    }

    /// Soft magnet at 0° — snaps within half a degree.
    mutating func setStraighten(_ degrees: Double) {
        let magnet: Double = abs(degrees) < 0.5 ? 0 : degrees
        working.straightenDegrees = min(max(magnet, -45), 45)
    }

    mutating func panPhoto(dx: Double, dy: Double) {
        working.photoPanX = min(max(working.photoPanX + dx, -1), 1)
        working.photoPanY = min(max(working.photoPanY + dy, -1), 1)
    }

    mutating func rotate(by delta: Double) {
        setStraighten(working.straightenDegrees + delta)
    }
}

enum CropSessionCopy {
    static func header(straightenDegrees: Double) -> String {
        String(format: "CROP — straighten %.1f° · ⏎ applies · Esc dismisses", straightenDegrees)
    }
}
