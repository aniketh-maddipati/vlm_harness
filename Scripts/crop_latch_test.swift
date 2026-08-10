#!/usr/bin/env swift
/**
 Crop latch state tests — frame C acceptance (layout hash, key semantics, grid flag).

 Run: swift Scripts/crop_latch_test.swift
 */
import Foundation

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond { print("PASS: \(msg)") } else { print("FAIL: \(msg)"); failures += 1 }
}

// MARK: - Mirrors (keep in sync with Lumina/Develop/CropSession.swift)

struct EditCrop: Equatable {
    var x, y, width, height: Double
    static let full = EditCrop(x: 0, y: 0, width: 1, height: 1)
    func normalized() -> EditCrop {
        let w = min(max(width, 0.01), 1)
        let h = min(max(height, 0.01), 1)
        return EditCrop(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h), width: w, height: h)
    }
    var fingerprint: String {
        String(format: "%.5f,%.5f,%.5f,%.5f", x, y, width, height)
    }
}

struct CropLayoutState: Equatable {
    var crop: EditCrop
    var straightenDegrees: Double
    var photoPanX: Double
    var photoPanY: Double
    var orientationFlipped: Bool
    var aspectUnlocked: Bool

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

struct CropSession: Equatable {
    var photoID: UUID
    var baseline: CropLayoutState
    var working: CropLayoutState
    var isDraggingOutside: Bool = false

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

    mutating func setStraighten(_ degrees: Double) {
        let magnet: Double = abs(degrees) < 0.5 ? 0 : degrees
        working.straightenDegrees = min(max(magnet, -45), 45)
    }
}

enum CropKeyScope {
    case idle
    case cropLatched

    func handlesA(isRepeat: Bool) -> CropKeyAction? {
        guard !isRepeat else { return nil }
        switch self {
        case .idle: return .stageDevelop
        case .cropLatched: return .toggleAspectLock
        }
    }

    func handlesX(isRepeat: Bool) -> CropKeyAction? {
        guard !isRepeat else { return nil }
        switch self {
        case .idle: return .reject
        case .cropLatched: return .flipOrientation
        }
    }
}

enum CropKeyAction: Equatable {
    case stageDevelop
    case reject
    case toggleAspectLock
    case flipOrientation
}

// MARK: - Tests

let baseline = CropLayoutState(
    crop: EditCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.6),
    straightenDegrees: 0,
    photoPanX: 0,
    photoPanY: 0,
    orientationFlipped: false,
    aspectUnlocked: false
)
let baselineHash = baseline.layoutHash

var session = CropSession(photoID: UUID(), baseline: baseline, working: baseline)
session.working.photoPanX = 0.3
session.working.straightenDegrees = 2.4
session.working.orientationFlipped = true
expect(session.working.layoutHash != baselineHash, "edits change layout hash")

session.revert()
expect(session.working.layoutHash == baselineHash, "Esc revert restores baseline layout hash pixel-exact")

var scope = CropKeyScope.cropLatched
expect(scope.handlesX(isRepeat: false) == .flipOrientation, "X in crop flips orientation")
expect(scope.handlesX(isRepeat: false) != .reject, "X in crop never marks reject")
expect(scope.handlesA(isRepeat: false) == .toggleAspectLock, "A in crop toggles aspect lock")
expect(scope.handlesA(isRepeat: false) != .stageDevelop, "A in crop never stages Develop")
expect(scope.handlesA(isRepeat: true) == nil, "A swallows autorepeat in crop")

scope = .idle
expect(scope.handlesA(isRepeat: false) == .stageDevelop, "A idle stages Develop")
expect(scope.handlesX(isRepeat: false) == .reject, "X idle rejects")

var magnetSession = CropSession(photoID: UUID(), baseline: baseline, working: baseline)
magnetSession.setStraighten(0.2)
expect(abs(magnetSession.working.straightenDegrees) < 0.01, "straighten soft magnet snaps near 0°")
magnetSession.setStraighten(3.7)
expect(abs(magnetSession.working.straightenDegrees - 3.7) < 0.01, "straighten away from 0 stays continuous")

session = CropSession(photoID: UUID(), baseline: baseline, working: baseline)
session.isDraggingOutside = true
expect(session.isDraggingOutside, "grid flag set while dragging outside")
session.revert()
expect(!session.isDraggingOutside, "grid flag clears on revert")

var panState = baseline
panState.photoPanX = 0.5
expect(panState.effectiveCrop.x < baseline.crop.x, "pan shifts effective crop")

if failures == 0 {
    print("\nAll crop latch tests passed.")
} else {
    print("\n\(failures) crop latch test(s) failed.")
    exit(1)
}
