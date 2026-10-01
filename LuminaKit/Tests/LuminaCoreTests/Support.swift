import XCTest
@testable import LuminaCore

// WP-0. Shared helpers for headless tests: a model on a virtual clock, driven by keys, read
// through the same `debug.state` JSON the UI tests read. No window, no focus, milliseconds per flow.

let parityDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../design/handoff/lumina-app/parity").standardizedFileURL

@MainActor
final class Harness {
    let clock = TestScheduler()
    let model: AppModel
    let exporter = RecordingExporter()
    let store: any PersistenceStore

    init(card: String = "demo117", copyRate: Int = 66, store: (any PersistenceStore)? = nil, window: CGSize = CGSize(width: 1100, height: 760)) {
        Faults.shared.clearAll(); ErrorFunnel.reset()
        let s = store ?? MemoryPersistence(); self.store = s
        var config = LaunchConfig(arguments: ["-LuminaUITest", "YES"], environment: ["LUMINA_CARD": card, "LUMINA_COPY_RATE": String(copyRate), "LUMINA_INTRO": "skip"])
        config.window = window
        model = AppModel.launch(config: config, services: Services(images: DefaultImageProvider(), exporter: exporter, persistence: s), clock: clock)
        model.windowSize = window
    }

    struct State: Decodable {
        struct Saved: Decodable, Equatable { let sig: String; let n: Int; let ne: Int; let fmt: String; let again: Bool }
        struct Import: Decodable { let busy: Bool; let n: Int; let msg: String?; let local: Bool }
        let step: String; let cur: String?; let copied: Int; let total: Int
        let kept: Int; let out: Int; let undecided: Int
        let keep: [String: Bool]; let look: [String: Double]; let looksCount: Int; let lookBytes: Int
        let zoom: Double; let overlay: String?; let saved: Saved?; let `import`: Import?; let errors: Int
    }
    var state: State { try! JSONDecoder().decode(State.self, from: Data(model.debugStateJSON.utf8)) }

    func wait(_ s: TimeInterval) { clock.advance(s) }
    /// "r", "cmd+z", "cmd+shift+z", "shift+.", "return", "left"… then `settle` seconds pass.
    func key(_ spec: String, settle: TimeInterval = 0.05, isRepeat: Bool = false) {
        var parts = spec.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        var k = parts.removeLast(); if k.isEmpty { k = "+" }
        var m: KeyModifiers = []
        if parts.contains("cmd") { m.insert(.command) }; if parts.contains("shift") { m.insert(.shift) }; if parts.contains("alt") { m.insert(.option) }
        model.handle(KeyEvent(k, m, isRepeat: isRepeat)); model.handle(KeyEvent(k, m, phase: .up)); clock.advance(settle)
    }
    func hold(_ k: String) { model.handle(KeyEvent(k)) }
    func release(_ k: String) { model.handle(KeyEvent(k, phase: .up)) }
    func go(_ n: Int, settle: TimeInterval = 0.6) { key("cmd+\(n)", settle: settle) }
    /// ⏎ on Open, then the whole card copied.
    func startCulling() { key("return"); clock.advance(Double(model.total) / (model.config.copyRate ?? 66) + 1) }
    func keepN(_ n: Int) { for _ in 0..<n { key("r", settle: 0.04) } }
}
