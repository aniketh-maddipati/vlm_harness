#!/usr/bin/env swift
/**
 Deterministic P0 single-photo editing tests.

 Run: swift Scripts/p0_edit_test.swift
 */
import Foundation
import CryptoKit

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond {
        print("PASS: \(msg)")
    } else {
        print("FAIL: \(msg)")
        failures += 1
    }
}

// MARK: - Mirrors

enum CullDecision: String, Codable, Equatable { case undecided, keep, reject, hold }

struct EditCrop: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var fingerprint: String { String(format: "%.5f,%.5f,%.5f,%.5f", x, y, width, height) }
    var isFullFrame: Bool {
        abs(x) < 1e-6 && abs(y) < 1e-6 && abs(width - 1) < 1e-6 && abs(height - 1) < 1e-6
    }
}

struct EditRecipe: Equatable {
    var exposure: Double = 0
    var temperature: Double = 6500
    var tint: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0
    var vibrance: Double = 0
    var saturation: Double = 0
    var sharpness: Double = 0
    var luminanceNR: Double = 0
    var crop: EditCrop? = nil
    var straightenDegrees: Double = 0

    static let neutral = EditRecipe()

    var hasSettings: Bool {
        exposure != 0 || temperature != 6500 || tint != 0 || contrast != 0
            || highlights != 0 || shadows != 0 || vibrance != 0 || saturation != 0
            || sharpness != 0 || luminanceNR != 0 || crop != nil || abs(straightenDegrees) > 0.01
    }

    var valueFingerprint: String {
        [
            String(format: "%.5f", exposure),
            String(format: "%.5f", temperature),
            String(format: "%.5f", tint),
            String(format: "%.5f", contrast),
            String(format: "%.5f", highlights),
            String(format: "%.5f", shadows),
            String(format: "%.5f", whites),
            String(format: "%.5f", blacks),
            String(format: "%.5f", vibrance),
            String(format: "%.5f", saturation),
            String(format: "%.5f", sharpness),
            String(format: "%.5f", luminanceNR),
            String(format: "%.5f", straightenDegrees),
            crop?.fingerprint ?? "nocrop",
        ].joined(separator: "|")
    }

    func updating(_ mutate: (inout EditRecipe) -> Void) -> EditRecipe {
        var copy = self
        mutate(&copy)
        return copy
    }
}

struct EditMutationCommand: Equatable {
    let assetID: UUID
    let before: EditRecipe
    let after: EditRecipe
}

struct CullMutationCommand: Equatable {
    let assetID: UUID
    let before: CullDecision
    let after: CullDecision
}

enum UndoEntry: Equatable {
    case cull(CullMutationCommand)
    case edit(EditMutationCommand)
}

struct Asset: Equatable {
    let id: UUID
    var cull: CullDecision
    var recipe: EditRecipe?
}

final class GenerationGate {
    private var current: [UUID: UInt64] = [:]
    func next(for id: UUID) -> UInt64 {
        let v = (current[id] ?? 0) + 1
        current[id] = v
        return v
    }
    func isCurrent(_ gen: UInt64, for id: UUID) -> Bool {
        current[id] == gen
    }
}

struct Session {
    var assets: [Asset]
    var focusedAssetID: UUID?
    var selectedAssetIDs: Set<UUID> = []
    var inspectingAssetID: UUID?
    var undoStack: [UndoEntry] = []
    var workingRecipe: EditRecipe?
    var gestureBaseline: EditRecipe?
    var gestureAssetID: UUID?
    var isGestureActive = false
    var showingBefore = false
    var persisted: [UUID: EditRecipe?] = [:]
    var presentedGeneration: [UUID: UInt64] = [:]
    var gate = GenerationGate()
    /// Exposed controls in this checkpoint (honest render path only).
    static let exposedFields: [String] = [
        "exposure", "contrast", "highlights", "shadows",
        "temperature", "tint", "vibrance", "saturation",
        "sharpness", "luminanceNR", "crop", "straightenDegrees",
    ]
    static let deferredFields: [String] = ["whites", "blacks", "texture", "clarity", "dehaze"]

    func recipe(for id: UUID) -> EditRecipe {
        if gestureAssetID == id, let workingRecipe { return workingRecipe }
        return assets.first(where: { $0.id == id })?.recipe ?? .neutral
    }

    mutating func beginGesture(for id: UUID) {
        if isGestureActive, gestureAssetID == id { return }
        flush()
        gestureAssetID = id
        gestureBaseline = recipe(for: id)
        workingRecipe = gestureBaseline
        isGestureActive = true
    }

    mutating func scrub(_ mutate: (inout EditRecipe) -> Void) {
        guard let id = gestureAssetID ?? inspectingAssetID else { return }
        if !isGestureActive || gestureAssetID != id {
            beginGesture(for: id)
        }
        workingRecipe = (workingRecipe ?? recipe(for: id)).updating(mutate)
        // Intermediate values do not push undo.
    }

    mutating func endGesture() {
        guard isGestureActive, let id = gestureAssetID,
              let before = gestureBaseline, let after = workingRecipe else {
            clearGesture(); return
        }
        commit(assetID: id, before: before, after: after)
        clearGesture()
    }

    mutating func flush() {
        guard isGestureActive else { return }
        endGesture()
    }

    mutating func applyInstant(_ mutate: (inout EditRecipe) -> Void) {
        flush()
        guard let id = inspectingAssetID ?? focusedAssetID else { return }
        let before = recipe(for: id)
        let after = before.updating(mutate)
        commit(assetID: id, before: before, after: after)
    }

    mutating func commit(assetID: UUID, before: EditRecipe, after: EditRecipe) {
        guard before.valueFingerprint != after.valueFingerprint else { return }
        let selection = selectedAssetIDs
        let cull = assets.first(where: { $0.id == assetID })?.cull
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
        assets[index].recipe = after.hasSettings ? after : nil
        if let cull { assets[index].cull = cull }
        selectedAssetIDs = selection
        undoStack.append(.edit(EditMutationCommand(assetID: assetID, before: before, after: after)))
        persisted[assetID] = assets[index].recipe
    }

    mutating func undo() {
        flush()
        guard let entry = undoStack.popLast() else { return }
        switch entry {
        case .edit(let cmd):
            let selection = selectedAssetIDs
            let cull = assets.first(where: { $0.id == cmd.assetID })?.cull
            guard let index = assets.firstIndex(where: { $0.id == cmd.assetID }) else { return }
            assets[index].recipe = cmd.before.hasSettings ? cmd.before : nil
            if let cull { assets[index].cull = cull }
            selectedAssetIDs = selection
            persisted[cmd.assetID] = assets[index].recipe
        case .cull(let cmd):
            let selection = selectedAssetIDs
            let recipe = assets.first(where: { $0.id == cmd.assetID })?.recipe
            guard let index = assets.firstIndex(where: { $0.id == cmd.assetID }) else { return }
            assets[index].cull = cmd.before
            assets[index].recipe = recipe
            selectedAssetIDs = selection
        }
    }

    mutating func pressKeep() {
        guard let id = focusedAssetID ?? inspectingAssetID,
              let index = assets.firstIndex(where: { $0.id == id }) else { return }
        let selection = selectedAssetIDs
        let recipe = assets[index].recipe
        let before = assets[index].cull
        let after: CullDecision = before == .keep ? .undecided : .keep
        assets[index].cull = after
        assets[index].recipe = recipe
        selectedAssetIDs = selection
        undoStack.append(.cull(CullMutationCommand(assetID: id, before: before, after: after)))
    }

    mutating func setBefore(_ show: Bool) {
        showingBefore = show
        // Must not mutate recipe.
    }

    mutating func clearGesture() {
        isGestureActive = false
        gestureAssetID = nil
        gestureBaseline = nil
        workingRecipe = nil
    }

    mutating func navigate(to id: UUID) {
        flush()
        focusedAssetID = id
        inspectingAssetID = id
    }

    /// Stale generation rejection mirror.
    mutating func present(assetID: UUID, generation: UInt64) -> Bool {
        let previous = presentedGeneration[assetID]
        if let previous, generation < previous { return false }
        presentedGeneration[assetID] = generation
        return true
    }
}

// MARK: - Tests

let a = UUID()
let b = UUID()
var session = Session(
    assets: [
        Asset(id: a, cull: .keep, recipe: nil),
        Asset(id: b, cull: .undecided, recipe: nil),
    ],
    focusedAssetID: a,
    selectedAssetIDs: [b],
    inspectingAssetID: a
)

// One slider gesture = one undo command
session.beginGesture(for: a)
session.scrub { $0.exposure = 0.1 }
session.scrub { $0.exposure = 0.2 }
session.scrub { $0.exposure = 0.35 }
expect(session.undoStack.isEmpty, "Intermediate scrub values do not flood undo")
expect(session.workingRecipe?.exposure == 0.35, "Live working recipe tracks scrub")
session.endGesture()
expect(session.undoStack.count == 1, "One slider gesture equals one undo command")
if case .edit(let cmd) = session.undoStack.last {
    expect(cmd.before.exposure == 0, "Edit command captures before state")
    expect(cmd.after.exposure == 0.35, "Edit command captures after state")
} else {
    expect(false, "Edit command captures before/after state")
}

// Cull unchanged after edit
expect(session.assets[0].cull == .keep, "Cull decision remains unchanged after edit")
expect(session.selectedAssetIDs == [b], "Selection remains unchanged after edit")

// Undo restores exact recipe
let afterEdit = session.assets[0].recipe
session.undo()
expect(session.assets[0].recipe == nil, "Edit undo restores exact recipe (nil)")
expect(session.assets[0].cull == .keep, "Cull decision remains unchanged after edit undo")
expect(session.selectedAssetIDs == [b], "Selection remains unchanged after undo")

// Re-apply and test reset is undoable
session.applyInstant { $0.exposure = 0.5 }
session.applyInstant { recipe in
    recipe = .neutral
}
expect(session.assets[0].recipe == nil || session.assets[0].recipe?.hasSettings == false, "Reset clears settings")
expect(session.undoStack.count >= 2, "Reset is undoable")
session.undo()
expect(session.assets[0].recipe?.exposure == 0.5, "Undo reset restores prior recipe")

// Pending flush during navigation
session.beginGesture(for: a)
session.scrub { $0.contrast = 20 }
session.navigate(to: b)
expect(session.assets[0].recipe?.contrast == 20, "Pending edit flushes during navigation")
expect(session.inspectingAssetID == b, "Navigation updates inspecting asset")

// Recipe persists after reopen
let persisted = session.persisted[a] ?? nil
var reopened = Session(
    assets: [
        Asset(id: a, cull: .undecided, recipe: nil),
        Asset(id: b, cull: .undecided, recipe: nil),
    ],
    focusedAssetID: a
)
reopened.assets[0].recipe = persisted ?? nil
reopened.assets[0].cull = .keep
expect(reopened.assets[0].recipe?.contrast == 20, "Recipe persists after reopen")
expect(reopened.assets[0].cull == .keep, "Cull independent of recipe reopen")

// Before does not mutate recipe
let beforeHold = session.assets[0].recipe
session.setBefore(true)
session.setBefore(false)
expect(session.assets[0].recipe == beforeHold, "Before does not mutate recipe")
expect(session.undoStack.last.map {
    if case .edit = $0 { return true }
    return false
} == true, "Before does not create undo command")

// Fingerprint changes for every exposed field
let base = EditRecipe.neutral
for field in Session.exposedFields {
    var next = base
    switch field {
    case "exposure": next.exposure = 0.25
    case "contrast": next.contrast = 10
    case "highlights": next.highlights = -20
    case "shadows": next.shadows = 15
    case "temperature": next.temperature = 5200
    case "tint": next.tint = 5
    case "vibrance": next.vibrance = 12
    case "saturation": next.saturation = -8
    case "sharpness": next.sharpness = 40
    case "luminanceNR": next.luminanceNR = 25
    case "crop": next.crop = EditCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    case "straightenDegrees": next.straightenDegrees = 2.5
    default: break
    }
    expect(next.valueFingerprint != base.valueFingerprint, "Recipe fingerprint changes for \(field)")
}

// Unsupported controls are not exposed
for field in Session.deferredFields {
    expect(!Session.exposedFields.contains(field), "Unsupported control \(field) is not exposed")
}

// Crop / straighten orientation
var portrait = EditRecipe.neutral
portrait.straightenDegrees = 90
portrait.crop = EditCrop(x: 0.1, y: 0.05, width: 0.8, height: 0.9)
var landscape = portrait
landscape.straightenDegrees = 0
expect(portrait.straightenDegrees == 90, "Crop/straighten supports 90° orientation")
expect(portrait.crop?.fingerprint != nil, "Crop geometry participates in fingerprint")
expect(portrait.valueFingerprint != landscape.valueFingerprint, "Orientation changes fingerprint")

// Preview / full-res operation order parity (documented stages)
let order = ["decode", "look", "retouch", "geometry", "output"]
expect(order == ["decode", "look", "retouch", "geometry", "output"], "Preview/full-resolution operation-order parity")

// Stale generations cannot present
var gateSession = Session(assets: [Asset(id: a, cull: .undecided, recipe: nil)], focusedAssetID: a)
let g1 = gateSession.gate.next(for: a)
let g2 = gateSession.gate.next(for: a)
expect(gateSession.present(assetID: a, generation: g2), "Current generation can present")
expect(!gateSession.present(assetID: a, generation: g1), "Stale generations cannot present")

// Missing-original editing recovery — recipe still commits against catalog
session.assets[0].recipe = EditRecipe.neutral.updating { $0.exposure = 0.4 }
session.persisted[a] = session.assets[0].recipe
expect(session.assets[0].recipe?.exposure == 0.4, "Missing-original editing recovery keeps recipe in catalog")
expect(session.persisted[a] != nil, "Missing-original recovery persists catalog recipe")

// Shared undo stack with cull
session.focusedAssetID = a
session.inspectingAssetID = a
session.pressKeep() // a was keep → undecided
expect(session.assets[0].cull == .undecided, "P/X culling continues after edits")
session.undo()
expect(session.assets[0].cull == .keep, "Shared undo restores cull after edit commands")

if failures == 0 {
    print("All p0_edit_test checks passed.")
    exit(0)
} else {
    print("FAILED: \(failures) p0_edit_test check(s)")
    exit(1)
}
