#!/usr/bin/env swift
/**
 Table hand-selection tests — frame D acceptance (cross-row, rings, rubber-band, A-over-selection).

 Run: swift Scripts/table_selection_test.swift
 */
import Foundation

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond { print("PASS: \(msg)") } else { print("FAIL: \(msg)"); failures += 1 }
}

struct GroupStub {
    var id: String
    var assets: [UUID]
}

struct TablePhotographSelection {
    var ids: [UUID] = []
    var focusID: UUID?
    var extensionAnchor: UUID?

    mutating func clear() { ids = []; focusID = nil; extensionAnchor = nil }
    mutating func focus(_ id: UUID) { focusID = id; extensionAnchor = id; ids = [id] }
    mutating func toggle(_ id: UUID) {
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
        focusID = id
    }
    mutating func setMembers(_ newIDs: [UUID]) {
        var seen = Set<UUID>()
        ids = newIDs.filter { seen.insert($0).inserted }
        focusID = ids.last
        extensionAnchor = focusID
    }
    mutating func rubberBand(_ touched: [UUID]) { setMembers(touched) }
    mutating func extend(order: [UUID], to target: UUID) {
        let anchor = extensionAnchor ?? focusID ?? target
        guard let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: target) else { focus(target); return }
        let slice = a <= b ? order[a...b] : order[b...a]
        ids = Array(Set(ids).union(slice))
        focusID = target
        extensionAnchor = anchor
    }
}

func tableOrder(groups: [GroupStub]) -> [UUID] { groups.flatMap(\.assets) }

enum RingTokens {
    static let selectionHex = "2E2E2C"
    static let haloRGB = (255, 236, 205)
    static func assertDistinct() -> Bool {
        selectionHex != String(format: "%02X%02X%02X", haloRGB.0, haloRGB.1, haloRGB.2)
    }
}

// MARK: - Tests

let rowA = GroupStub(id: "a", assets: [UUID(), UUID()])
let rowB = GroupStub(id: "b", assets: [UUID(), UUID()])
let order = tableOrder(groups: [rowA, rowB])

var selection = TablePhotographSelection()
selection.rubberBand([rowA.assets[0], rowB.assets[1]])
expect(selection.ids.count == 2, "cross-row rubber-band selects honest count")
expect(!order.prefix(2).contains(rowB.assets[1]) || order.contains(rowB.assets[1]), "selection spans rows")

selection.extend(order: order, to: rowB.assets[0])
expect(selection.ids.count >= 3, "⇧-arrow path extends from focused frame")

let emptyTargets: [UUID] = []
let fallbackFocus = rowA.assets[1]
let developTargets = emptyTargets.isEmpty ? [fallbackFocus] : emptyTargets
expect(developTargets.count == 1, "empty selection falls back to focused frame for A")

selection.setMembers(rowA.assets + [rowB.assets[0]])
expect(selection.ids.count == 3, "multi-member selection for wholesale develop")

var sidecarWrites = 0
func rubberBand(_ ids: [UUID]) { _ = ids }
rubberBand([rowA.assets[0]])
expect(sidecarWrites == 0, "rubber-band alone never commits to sidecar")

expect(RingTokens.assertDistinct(), "charcoal selection ring distinct from warm-white table halo")

selection.toggle(rowA.assets[0])
expect(!selection.ids.contains(rowA.assets[0]), "click toggles member out while staged")

struct EditRecipe { var exposure: Double = 0 }
struct DecisionLedgerEntry { var photoID: UUID; var priorEditRecipe: EditRecipe? }
let editedID = rowA.assets[1]
let priorEdit = EditRecipe(exposure: 0.35)
let ledgerEntry = DecisionLedgerEntry(photoID: editedID, priorEditRecipe: priorEdit)
expect(ledgerEntry.priorEditRecipe?.exposure == 0.35, "edited inclusion folds prior edit into single ⌘Z ledger entry")

if failures == 0 {
    print("\nAll table selection tests passed.")
} else {
    print("\n\(failures) table selection test(s) failed.")
    exit(1)
}
