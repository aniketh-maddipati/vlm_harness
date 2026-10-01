import XCTest

/// Drives the Lumina app through the accessibility contract (ACCESSIBILITY_CONTRACT.md).
/// Every suite builds on this; no test reaches into views by position.
final class Lumina {
    let app = XCUIApplication()
    let storeDir: URL
    private(set) var launchedAt = Date()

    init(card: String = "demo117", fixture: URL? = nil, window: CGSize = CGSize(width: 1100, height: 760),
         faults: [String] = [], copyRate: Int = 66, keepStore: URL? = nil) {
        storeDir = keepStore ?? FileManager.default.temporaryDirectory.appendingPathComponent("lumina-store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        app.launchArguments += ["-LuminaUITest", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["LUMINA_STORE_DIR"] = storeDir.path
        app.launchEnvironment["LUMINA_CARD"] = card
        app.launchEnvironment["LUMINA_COPY_RATE"] = String(copyRate)
        app.launchEnvironment["LUMINA_WINDOW"] = "\(Int(window.width))x\(Int(window.height))"
        app.launchEnvironment["LUMINA_INTRO"] = "skip"
        if let fixture { app.launchEnvironment["LUMINA_FIXTURE"] = fixture.path }
        if !faults.isEmpty { app.launchEnvironment["LUMINA_FAULTS"] = faults.joined(separator: ",") }
    }

    @discardableResult func launch() -> Lumina { app.launch(); launchedAt = Date(); XCTAssertTrue(el("step.cull").waitForExistence(timeout: 10), "app never showed its step tabs"); return self }
    /// Quit and relaunch against the same store (decisions/edits must survive, R-70).
    func relaunch() { app.terminate(); app.launch(); launchedAt = Date(); _ = el("step.cull").waitForExistence(timeout: 10) }

    // MARK: elements
    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    func all(prefix: String) -> [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
    }
    func exists(_ id: String, timeout: TimeInterval = 0) -> Bool { timeout > 0 ? el(id).waitForExistence(timeout: timeout) : el(id).exists }
    func value(_ id: String) -> String { (el(id).value as? String) ?? el(id).label }
    func click(_ id: String, times: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        let e = el(id); XCTAssertTrue(e.waitForExistence(timeout: 3), "missing \(id)", file: file, line: line)
        for _ in 0..<times { e.click() }
    }

    // MARK: state hook
    struct State: Decodable {
        struct Saved: Decodable { let sig: String; let n: Int; let ne: Int; let fmt: String; let again: Bool }
        struct Import: Decodable { let busy: Bool; let n: Int; let msg: String?; let local: Bool }
        let step: String; let cur: String?; let copied: Int; let total: Int
        let kept: Int; let out: Int; let undecided: Int
        let keep: [String: Bool]; let look: [String: Double]; let looksCount: Int; let lookBytes: Int
        let zoom: Double; let overlay: String?; let saved: Saved?; let `import`: Import?; let errors: Int
    }
    var state: State {
        let raw = value("debug.state")
        do { return try JSONDecoder().decode(State.self, from: Data(raw.utf8)) }
        catch { XCTFail("debug.state unreadable: \(raw.prefix(200))"); fatalError() }
    }
    struct Metrics: Decodable {
        struct Row: Decodable { let scene: Int; let width: Double; let gridWidth: Double; let last: Bool }
        let scale: Double; let minFontPt: Double; let bodyFontPt: Double; let fonts: [String: Double]
        let canvas: [Double]?; let photo: [Double]?; let tileH: Double?; let rows: [Row]?
    }
    var metrics: Metrics { try! JSONDecoder().decode(Metrics.self, from: Data(value("debug.metrics").utf8)) }

    func command(_ json: String) {
        let f = el("debug.command"); XCTAssertTrue(f.waitForExistence(timeout: 2))
        f.click(); f.typeText(json + "\r")
    }
    func resize(_ w: CGFloat, _ h: CGFloat, settle: TimeInterval = 0.25) { command("{\"resize\":[\(Int(w)),\(Int(h))]}"); pause(settle) }
    func blurWindow() { command("{\"blur\":true}") }

    // MARK: keys
    func key(_ k: String, _ mods: XCUIElement.KeyModifierFlags = []) { app.typeKey(k, modifierFlags: mods) }
    func cmd(_ k: String) { key(k, .command) }
    func go(_ step: Int, settle: TimeInterval = 0.6) { cmd("\(step)"); pause(settle) }
    func enter() { key(XCUIKeyboardKey.return.rawValue) }
    func esc() { key(XCUIKeyboardKey.escape.rawValue) }
    func left() { key(XCUIKeyboardKey.leftArrow.rawValue) }
    func right() { key(XCUIKeyboardKey.rightArrow.rawValue) }
    /// Hold a key for `duration` (variations V, before \). XCUITest has no key-down API on macOS,
    /// so the app exposes holds through the command hook in UI-test builds.
    func hold(_ k: String, for duration: TimeInterval, during: () -> Void = {}) {
        command("{\"keyDown\":\"\(k)\"}"); pause(duration); during(); command("{\"keyUp\":\"\(k)\"}")
    }

    // MARK: waiting
    func pause(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
    @discardableResult func waitUntil(_ timeout: TimeInterval = 5, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; pause(0.05) }
        return cond()
    }
    func waitCopied(_ n: Int, timeout: TimeInterval = 15) -> Bool { waitUntil(timeout) { state.copied >= n } }

    // MARK: common flows
    func startCulling(waitAll: Bool = true) { enter(); if waitAll { XCTAssertTrue(waitCopied(state.total, timeout: 60), "copy never finished") } ; pause(0.3) }
    func keepN(_ n: Int) { for _ in 0..<n { key("r"); pause(0.04) } }
    func importFixture(_ url: URL) { command("{\"drop\":[\"\(url.path)\"]}"); waitUntil(30) { !(state.import?.busy ?? false) } }

    // MARK: layout probes
    var window: XCUIElement { app.windows.firstMatch }
    func hasHorizontalScroll() -> Bool {
        let w = window.frame
        return app.scrollViews.allElementsBoundByIndex.contains { sv in
            sv.frame.width > w.width + 1 || (sv.scrollBars.matching(NSPredicate(format: "orientation == 0")).count > 0)
        }
    }
    func visible(_ e: XCUIElement) -> Bool { e.exists && e.isHittable && e.frame.width > 0 && e.frame.height > 0 }
    func alive() -> String? {
        guard app.state == .runningForeground else { return "app not running (\(app.state.rawValue))" }
        guard el("step.cull").isHittable else { return "tabs not reachable" }
        return nil
    }
}

extension XCTestCase {
    func percentile(_ a: [Double], _ p: Double) -> Double { let s = a.sorted(); return s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * p))] }
    /// Every suite ends here: zero unexpected errors (R-73).
    func assertNoErrors(_ l: Lumina, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(l.state.errors, 0, "R-73 unexpected errors", file: file, line: line)
    }
}
