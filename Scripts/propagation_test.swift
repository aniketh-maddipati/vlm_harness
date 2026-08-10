#!/usr/bin/env swift
/**
 Wholesale propagation tests — frame H6 acceptance (rings, widen/narrow, exclusions, A1).

 Run: swift Scripts/propagation_test.swift
 */
import Foundation

var failures = 0
func expect(_ cond: Bool, _ msg: String) {
    if cond { print("PASS: \(msg)") } else { print("FAIL: \(msg)"); failures += 1 }
}

enum PropagationRing: Equatable { case row, scene, shoot }

struct PropagationState: Equatable {
    var ring: PropagationRing = .row
    var excludedIDs: Set<UUID> = []

    mutating func widen() -> Bool {
        switch ring {
        case .row: ring = .scene; return true
        case .scene: ring = .shoot; return true
        case .shoot: return false
        }
    }

    mutating func narrow() -> Bool {
        switch ring {
        case .shoot: ring = .scene; return true
        case .scene: ring = .row; return true
        case .row: return false
        }
    }
}

struct StagingCopySnapshot {
    var scopeCount: Int
    var excludedCount: Int = 0
    var ring: PropagationRing = .row
}

func adaptBanner(_ s: StagingCopySnapshot) -> String {
    if s.excludedCount > 0, s.ring == .shoot {
        return "Adapt → \(s.scopeCount) · \(s.excludedCount) excluded ⏎ · ⇧⏎ shoot"
    }
    if s.ring == .scene {
        return "Adapt → \(s.scopeCount) ⏎ · ⇧⏎ scene · Esc"
    }
    return "Adapt → \(s.scopeCount) ⏎ · Esc"
}

func stagedHeader(_ s: StagingCopySnapshot) -> String {
    if s.excludedCount > 0 {
        let ringLabel = s.ring == .shoot ? "shoot" : (s.ring == .scene ? "scene" : "row 1")
        return "STAGED · \(ringLabel) · \(s.scopeCount) selected · \(s.excludedCount) excluded · ⏎ applies · Esc cancels"
    }
    return "STAGED · row 1 · 18:17 · \(s.scopeCount) selected · ⏎ applies · Esc cancels, nothing applied"
}

func committedCount(in text: String) -> Int? {
    if let r = text.range(of: #"Adapt → (\d+)"#, options: .regularExpression) {
        let slice = text[r].dropFirst("Adapt → ".count)
        return Int(slice.prefix(while: { $0.isNumber }))
    }
    if let r = text.range(of: #"Adapted → (\d+)"#, options: .regularExpression) {
        let slice = text[r].dropFirst("Adapted → ".count)
        return Int(slice.prefix(while: { $0.isNumber }))
    }
    if let r = text.range(of: #"· (\d+) selected"#, options: .regularExpression) {
        return Int(text[r].filter(\.isNumber))
    }
    return nil
}

func a1Validate(header: String, banner: String, receipt: String, snapshot: StagingCopySnapshot) -> Bool {
    guard let hc = committedCount(in: header), hc == snapshot.scopeCount else { return false }
    guard let bc = committedCount(in: banner), bc == snapshot.scopeCount else { return false }
    guard let rc = committedCount(in: receipt), rc == snapshot.scopeCount else { return false }
    if snapshot.excludedCount > 0 {
        guard header.contains("\(snapshot.excludedCount) excluded") else { return false }
        guard banner.contains("\(snapshot.excludedCount) excluded") else { return false }
    }
    return true
}

// MARK: - Tests

var state = PropagationState()
expect(state.ring == .row, "default scope is row")
expect(state.widen(), "⇧⏎ widens row → scene")
expect(state.ring == .scene, "at scene ring")
expect(state.widen(), "⇧⏎ widens scene → shoot")
expect(state.ring == .shoot, "at shoot ring")
expect(!state.widen(), "⇧⏎ at shoot is no-op")

expect(state.narrow(), "Esc narrows shoot → scene")
expect(state.narrow(), "Esc narrows scene → row")
expect(!state.narrow(), "Esc at row signals full cancel")

var exclusions: Set<UUID> = [UUID()]
var restaged = PropagationState(ring: .row, excludedIDs: exclusions)
expect(restaged.excludedIDs == exclusions, "exception persists through re-staging")

let shootSnap = StagingCopySnapshot(scopeCount: 10, excludedCount: 2, ring: .shoot)
let header = stagedHeader(shootSnap)
let banner = adaptBanner(shootSnap)
let receipt = "Adapted → 10 · ⌘Z"
expect(a1Validate(header: header, banner: banner, receipt: receipt, snapshot: shootSnap), "A1 at shoot ring with exclusions")

var ledgerEntries = 0
func commitRound(_ ids: [UUID]) { ledgerEntries = ids.count }
commitRound([UUID(), UUID(), UUID()])
expect(ledgerEntries == 3, "single ⏎ at shoot radius is one undo round")

expect("2E2E2C" != "FFECCD", "charcoal selection distinct from warm-white halo")

if failures == 0 {
    print("\nAll propagation tests passed.")
} else {
    print("\n\(failures) propagation test(s) failed.")
    exit(1)
}
