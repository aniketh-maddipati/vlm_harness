#!/usr/bin/env swift
/**
 Deterministic P0 cull grammar + undo + restore tests.

 Run: swift Scripts/p0_cull_test.swift
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

struct CullMutationCommand: Equatable {
    let assetID: UUID
    let before: CullDecision
    let after: CullDecision
    let finalOrderBefore: [UUID]
    let finalOrderAfter: [UUID]

    static func resolveToggle(current: CullDecision, pressed: CullDecision) -> CullDecision {
        if current == pressed { return .undecided }
        return pressed
    }
}

struct FinalSetOrder: Equatable {
    var assetIDs: [UUID] = []
    var isCustom: Bool { !assetIDs.isEmpty }

    mutating func reconcileKeptMembership(keptIDsInChronologicalOrder: [UUID]) {
        guard isCustom else { return }
        let kept = Set(keptIDsInChronologicalOrder)
        assetIDs.removeAll { !kept.contains($0) }
        for id in keptIDsInChronologicalOrder where !assetIDs.contains(id) {
            assetIDs.append(id)
        }
    }
}

struct Asset: Equatable {
    let id: UUID
    var cull: CullDecision
    var recipe: String?
}

struct Session {
    var assets: [Asset]
    var focusedAssetID: UUID?
    var selectedAssetIDs: Set<UUID> = []
    var finalOrder = FinalSetOrder()
    var undoStack: [CullMutationCommand] = []
    var scrollAnchor: Double = 0
    var inspectingAssetID: UUID?
    var pendingScrollRestore = false

    var exportCount: Int { assets.filter { $0.cull == .keep }.count }

    mutating func press(_ pressed: CullDecision) {
        guard let focus = focusedAssetID,
              let index = assets.firstIndex(where: { $0.id == focus }) else { return }
        let selection = selectedAssetIDs
        let recipe = assets[index].recipe
        let before = assets[index].cull
        let after = CullMutationCommand.resolveToggle(current: before, pressed: pressed)
        guard before != after else { return }
        let orderBefore = finalOrder.assetIDs
        assets[index].cull = after
        assets[index].recipe = recipe
        let kept = assets.filter { $0.cull == .keep }.map(\.id)
        finalOrder.reconcileKeptMembership(keptIDsInChronologicalOrder: kept)
        let cmd = CullMutationCommand(
            assetID: focus,
            before: before,
            after: after,
            finalOrderBefore: orderBefore,
            finalOrderAfter: finalOrder.assetIDs
        )
        undoStack.append(cmd)
        selectedAssetIDs = selection
    }

    mutating func undo() {
        guard let cmd = undoStack.popLast(),
              let index = assets.firstIndex(where: { $0.id == cmd.assetID }) else { return }
        let selection = selectedAssetIDs
        let recipe = assets[index].recipe
        assets[index].cull = cmd.before
        assets[index].recipe = recipe
        finalOrder.assetIDs = cmd.finalOrderBefore
        selectedAssetIDs = selection
    }

    mutating func openPhoto() {
        inspectingAssetID = focusedAssetID
    }

    mutating func closePhoto() {
        pendingScrollRestore = true
        inspectingAssetID = nil
    }
}

// MARK: - Grammar

let a = UUID()
let b = UUID()
let c = UUID()
var session = Session(
    assets: [
        Asset(id: a, cull: .undecided, recipe: "exposure+0.3"),
        Asset(id: b, cull: .undecided, recipe: nil),
        Asset(id: c, cull: .undecided, recipe: nil),
    ],
    focusedAssetID: a,
    selectedAssetIDs: [b]
)

session.press(.keep)
expect(session.assets[0].cull == .keep, "Unreviewed → kept")
expect(session.assets[0].recipe == "exposure+0.3", "Cull state independent from recipe")
expect(session.selectedAssetIDs == [b], "Selection independent from focus / cull")
expect(session.focusedAssetID == a, "Focus unchanged by cull")

session.press(.keep)
expect(session.assets[0].cull == .undecided, "Kept → unreviewed by repeated P")

session.press(.reject)
expect(session.assets[0].cull == .reject, "Unreviewed → rejected")

session.press(.reject)
expect(session.assets[0].cull == .undecided, "Rejected → unreviewed by repeated X")

session.press(.keep)
session.press(.reject)
expect(session.assets[0].cull == .reject, "Kept → rejected")

session.press(.keep)
expect(session.assets[0].cull == .keep, "Rejected → kept")

// Undo restores exact prior state
let recipeBeforeUndo = session.assets[0].recipe
let selectionBeforeUndo = session.selectedAssetIDs
session.undo()
expect(session.assets[0].cull == .reject, "Undo restores exact prior cull state")
expect(session.assets[0].recipe == recipeBeforeUndo, "Undo leaves edit state unchanged")
expect(session.selectedAssetIDs == selectionBeforeUndo, "Undo leaves selection unchanged")

session.focusedAssetID = b
session.press(.keep)
session.focusedAssetID = c
session.press(.keep)
expect(session.exportCount == 2, "Export count equals kept count")
session.press(.reject) // c: keep → reject
expect(session.exportCount == 1, "Export count tracks kept set after reject")

// Reopen retains decisions (simulate save/load)
let persistedCulls = Dictionary(uniqueKeysWithValues: session.assets.map { ($0.id, $0.cull) })
var reopened = Session(
    assets: session.assets.map { Asset(id: $0.id, cull: .undecided, recipe: $0.recipe) },
    focusedAssetID: a
)
for i in reopened.assets.indices {
    reopened.assets[i].cull = persistedCulls[reopened.assets[i].id] ?? .undecided
}
expect(reopened.assets.map(\.cull) == session.assets.map(\.cull), "Reopen retains decisions")

// Grid → photograph → grid restores focus and scroll
session.focusedAssetID = b
session.scrollAnchor = 0.37
session.selectedAssetIDs = [a, c]
session.openPhoto()
expect(session.inspectingAssetID == b, "Return/open enters single-photo")
expect(session.selectedAssetIDs == [a, c], "Selection preserved while opening photograph")
session.closePhoto()
expect(session.inspectingAssetID == nil, "Escape returns to sheet")
expect(session.focusedAssetID == b, "Grid ← photo restores same focused cell")
expect(session.scrollAnchor == 0.37, "Scroll anchor preserved across scale change")
expect(session.pendingScrollRestore, "Pending scroll restore flagged on return")
expect(session.selectedAssetIDs == [a, c], "Selection preserved while closing photograph")

// Final order membership reconciliation (custom mode only)
var order = FinalSetOrder(assetIDs: [a, b])
order.reconcileKeptMembership(keptIDsInChronologicalOrder: [b, c])
expect(order.assetIDs == [b, c], "Custom final order reconciles kept membership")
var chrono = FinalSetOrder()
chrono.reconcileKeptMembership(keptIDsInChronologicalOrder: [a, b])
expect(chrono.assetIDs.isEmpty, "Chronological mode leaves final order empty")

// Toggle resolver unit
expect(CullMutationCommand.resolveToggle(current: .undecided, pressed: .keep) == .keep, "resolver keep")
expect(CullMutationCommand.resolveToggle(current: .keep, pressed: .keep) == .undecided, "resolver clear keep")
expect(CullMutationCommand.resolveToggle(current: .reject, pressed: .keep) == .keep, "resolver reject→keep")

if failures > 0 {
    fputs("p0_cull_test: \(failures) failure(s)\n", stderr)
    exit(1)
}
print("All p0_cull_test checks passed.")
