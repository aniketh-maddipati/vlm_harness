import XCTest
@testable import LuminaCore

/// The parity kit, headless: the demo card equals `demo-shoot-117.json`, and the six recorded
/// flows (`traces.json`) replay on the model with the same state after every action. The UI
/// version (`LuminaUITests/Native/TraceReplayTests.swift`) drives the real window; this one runs
/// in milliseconds and is every work package's first check.
@MainActor
final class ParityKitTests: XCTestCase {
    func test_demoCardMatchesTheParityKit() throws {
        struct File: Decodable {
            struct P: Decodable { let id: String; let scene: Int; let burst: String?; let aspect: Double; let suggested: Bool; let bw: Bool
                let lens: String; let fl: Double; let ap: String; let sh: String; let iso: Int; let time: String }
            struct S: Decodable { let index: Int; let start: String; let ids: [String] }
            struct B: Decodable { let id: String; let ids: [String] }
            let camera: String; let photos: [P]; let scenes: [S]; let bursts: [B]
        }
        let f = try JSONDecoder().decode(File.self, from: Data(contentsOf: parityDir.appendingPathComponent("demo-shoot-117.json")))
        let s = Shoot.demo117
        XCTAssertEqual(s.photos.count, f.photos.count); XCTAssertEqual(s.label, f.camera)
        for (a, b) in zip(s.photos, f.photos) {
            XCTAssertEqual(a.id, b.id); XCTAssertEqual(a.scene, b.scene, a.id); XCTAssertEqual(a.burst, b.burst, a.id)
            XCTAssertEqual(a.aspect, b.aspect, accuracy: 0.001, a.id); XCTAssertEqual(a.suggested, b.suggested, a.id)
            XCTAssertEqual(a.lens, b.lens, a.id); XCTAssertEqual(a.focal, b.fl, a.id); XCTAssertEqual(a.aperture.map { "f/" + String(format: "%g", $0) }, b.ap, a.id)
            XCTAssertEqual(a.shutter, b.sh, a.id); XCTAssertEqual(a.iso, b.iso, a.id); XCTAssertEqual(a.time, b.time, a.id)
            if case .demo(_, let bw) = a.source { XCTAssertEqual(bw, b.bw, a.id) } else { XCTFail("not a demo photo") }
        }
        XCTAssertEqual(s.scenes.map(\.ids), f.scenes.map(\.ids)); XCTAssertEqual(s.scenes.map(\.hm), f.scenes.map(\.start))
        XCTAssertEqual(s.bursts.map(\.ids), f.bursts.map(\.ids)); XCTAssertEqual(s.bursts.map(\.id), f.bursts.map(\.id))
    }

    struct Traces: Decodable {
        struct Flow: Decodable { let setup: String; let steps: [Step] }
        struct Step: Decodable {
            struct Saved: Decodable, Equatable { let n: Int; let ne: Int; let fmt: String; let again: Bool }
            let a: String; let step: String; let cur: String?; let kept: Int; let out: Int
            let dec: Bool?; let look: [String: Double]?; let overlay: String?; let zoom: Double?; let saved: Saved?
        }
        let flows: [String: Flow]
    }
    static let traces = try! JSONDecoder().decode(Traces.self, from: Data(contentsOf: parityDir.appendingPathComponent("traces/traces.json")))

    func test_trace_cullBasics() { replay("cull-basics") }
    func test_trace_stepSwitching() { replay("step-switching") }
    func test_trace_enterGuards() { replay("enter-guards") }
    func test_trace_editBasics() { replay("edit-basics") }
    func test_trace_editConflicts() { replay("edit-conflicts") }
    func test_trace_saveFlow() { replay("save-flow") }

    private func replay(_ name: String) {
        let flow = Self.traces.flows[name]!, h = Harness()
        switch flow.setup {
        case "copied": h.startCulling()
        case "kept6": h.startCulling(); h.keepN(6); h.wait(0.3)
        default: break
        }
        for (i, want) in flow.steps.enumerated() {
            if i > 0 { perform(want.a, h) }
            let got = h.state, at = "\(name) step \(i) “\(want.a)”"
            XCTAssertEqual(got.step, want.step, "\(at): step")
            if !(name == "enter-guards" && want.cur == nil) { XCTAssertEqual(got.cur, want.cur, "\(at): current photo") }
            XCTAssertEqual(got.kept, want.kept, "\(at): kept"); XCTAssertEqual(got.out, want.out, "\(at): out")
            if let d = want.dec, let c = got.cur { XCTAssertEqual(got.keep[c], d, "\(at): decision on current") }
            if got.step == "edit" {
                let wl = want.look ?? [:]
                XCTAssertEqual(Set(got.look.keys), Set(wl.keys), "\(at): edited settings")
                for (k, v) in wl { XCTAssertEqual(got.look[k] ?? .nan, v, accuracy: 0.001, "\(at): \(k)") }
                XCTAssertEqual(got.overlay, want.overlay, "\(at): overlay")
                XCTAssertEqual(got.zoom, want.zoom ?? 1, accuracy: 0.05, "\(at): zoom")
            }
            XCTAssertEqual(got.saved.map { Traces.Step.Saved(n: $0.n, ne: $0.ne, fmt: $0.fmt, again: $0.again) }, want.saved, "\(at): saved")
        }
        XCTAssertEqual(h.state.errors, 0, "R-73")
    }

    private func perform(_ a: String, _ h: Harness) {
        if a.hasPrefix("wait:") { h.wait(Double(a.dropFirst(5))! / 1000); return }
        switch a {
        case "v-hold": h.hold("v"); h.wait(0.4); return
        case "v-up": h.release("v"); h.wait(0.4); return
        case "click:save": h.model.saveNow(); h.wait(0.22); return
        case "click:fmt-jpeg": h.model.setFormat(.jpeg); h.wait(0.22); return
        default: break
        }
        var parts = a.split(separator: "+").map(String.init); let k = parts.removeLast()
        let names = ["Enter": "return", "Escape": "escape", "ArrowLeft": "left", "ArrowRight": "right", "ArrowUp": "up", "ArrowDown": "down",
                     "BracketRight": "]", "BracketLeft": "[", "Equal": "=", "Slash": "/"]
        let mods = parts.map { ["Meta": "cmd", "Shift": "shift", "Alt": "alt"][$0] ?? $0 }
        let settle = a.contains("Meta+3") ? 1.3 : a.range(of: #"Meta\+\d"#, options: .regularExpression) != nil ? 0.6 : a == "Enter" ? 0.12 : 0.22
        h.key((mods + [names[k] ?? k]).joined(separator: "+"), settle: settle)
    }
}
