import XCTest

/// Replays traces/traces.json against the native app and compares state after EVERY action (not just the end).
/// Copy traces.json into the UI-test bundle resources. Requires LUMINA_CARD=demo117 to reproduce demo-shoot-117.json ids exactly.
final class TraceReplayTests: XCTestCase {
    struct File: Decodable { let flows: [String: Flow] }
    struct Flow: Decodable { let setup: String; let steps: [Step] }
    struct Step: Decodable {
        struct Saved: Decodable, Equatable { let n: Int; let ne: Int; let fmt: String; let again: Bool }
        let a: String; let step: String; let cur: String?; let kept: Int; let out: Int
        let dec: Bool?; let look: [String: Double]?; let overlay: String?; let zoom: Double?; let saved: Saved?
    }
    static let file: File = {
        let url = Bundle(for: TraceReplayTests.self).url(forResource: "traces", withExtension: "json")!
        return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url))
    }()

    func test_trace_cullBasics() { replay("cull-basics") }
    func test_trace_stepSwitching() { replay("step-switching") }
    func test_trace_enterGuards() { replay("enter-guards") }
    func test_trace_editBasics() { replay("edit-basics") }
    func test_trace_editConflicts() { replay("edit-conflicts") }
    func test_trace_saveFlow() { replay("save-flow") }

    private func replay(_ name: String) {
        let flow = Self.file.flows[name]!, l = Lumina().launch()
        defer { assertNoErrors(l); l.app.terminate() }
        switch flow.setup {
        case "copied": l.startCulling()
        case "kept6": l.startCulling(); l.keepN(6); l.pause(0.3)
        default: break
        }
        for (i, want) in flow.steps.enumerated() {
            if i > 0 { perform(want.a, l) }
            let got = l.state, at = "\(name) step \(i) “\(want.a)”"
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
            XCTAssertEqual(got.saved.map { Step.Saved(n: $0.n, ne: $0.ne, fmt: $0.fmt, again: $0.again) }, want.saved, "\(at): saved")
        }
    }

    private func perform(_ a: String, _ l: Lumina) {
        if a.hasPrefix("wait:") { l.pause(Double(a.dropFirst(5))! / 1000); return }
        switch a {
        case "v-hold": l.command("{\"keyDown\":\"v\"}"); l.pause(0.4); return
        case "v-up": l.command("{\"keyUp\":\"v\"}"); l.pause(0.4); return
        case "click:save": l.click("save.button")
        case "click:fmt-jpeg": l.click("save.format.jpeg")
        default:
            var parts = a.split(separator: "+").map(String.init); let k = parts.removeLast()
            var m: XCUIElement.KeyModifierFlags = []
            if parts.contains("Meta") { m.insert(.command) }; if parts.contains("Shift") { m.insert(.shift) }; if parts.contains("Alt") { m.insert(.option) }
            let map: [String: String] = ["Enter": XCUIKeyboardKey.return.rawValue, "Escape": XCUIKeyboardKey.escape.rawValue,
                "ArrowLeft": XCUIKeyboardKey.leftArrow.rawValue, "ArrowRight": XCUIKeyboardKey.rightArrow.rawValue,
                "ArrowUp": XCUIKeyboardKey.upArrow.rawValue, "ArrowDown": XCUIKeyboardKey.downArrow.rawValue,
                "BracketRight": "]", "BracketLeft": "[", "Equal": "=", "Slash": "/"]
            l.key(map[k] ?? k, m)
        }
        l.pause(a.contains("Meta+3") ? 1.3 : a.range(of: #"Meta\+\d"#, options: .regularExpression) != nil ? 0.6 : a == "Enter" ? 0.12 : 0.22)
    }
}
