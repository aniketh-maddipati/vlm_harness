import XCTest

/// Drives the Lumina app through the accessibility contract (ACCESSIBILITY_CONTRACT.md).
/// Every suite builds on this; no test reaches into views by position.
final class Lumina {
    let app = XCUIApplication()
    let storeDir: URL
    let copyRate: Int
    private(set) var launchedAt = Date()
    private let ownsStore: Bool

    // MARK: ending (LuminaTestCase)
    /// LUMINA_LONG=1 (TEST_RUNNER_LUMINA_LONG for xcodebuild; Scripts/test.sh passes it): the long
    /// version of a loop (every window shape) and the suites that only run on purpose.
    static let long = ProcessInfo.processInfo.environment["LUMINA_LONG"] == "1"
    private(set) static weak var current: XCTestCase?
    private static var launched: [Lumina] = []
    static func begin(_ test: XCTestCase) { current = test; launched = [] }
    /// After every test, pass or fail: no app left running, no store folder left in the temp folder.
    static func endAll() {
        for l in launched {
            if l.app.state != .notRunning { l.app.terminate() }
            if l.ownsStore { try? FileManager.default.removeItem(at: l.storeDir) }
        }
        TestGuard.killApp()
        launched = []
    }
    /// A precondition of everything that follows is broken: one failure that says so, and the
    /// test ends (the helpers below do nothing from here on, and the next failed assertion in
    /// the test stops it) instead of each later check waiting for an app that is not there.
    static func preconditionFailed(_ why: String, file: StaticString = #filePath, line: UInt = #line) {
        guard TestGuard.stopped == nil else { return }
        TestGuard.stop(why)
        current?.continueAfterFailure = true
        XCTFail(why + ": the test stops here", file: file, line: line)
        current?.continueAfterFailure = false
    }
    /// True once the test must not go on (a broken precondition, or its time limit).
    private var off: Bool {
        guard TestGuard.stopped != nil else { return false }
        Lumina.current?.continueAfterFailure = false
        return true
    }

    init(card: String = "demo117", fixture: URL? = nil, window: CGSize = CGSize(width: 1100, height: 760),
         faults: [String] = [], copyRate: Int = 66, keepStore: URL? = nil) {
        self.copyRate = copyRate
        ownsStore = keepStore == nil
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
        Lumina.launched.append(self)
    }

    @discardableResult func launch(file: StaticString = #filePath, line: UInt = #line) -> Lumina {
        guard !off else { return self }
        app.launch(); launchedAt = Date()
        if !app.wait(for: .runningForeground, timeout: 10) {
            Lumina.preconditionFailed("the app did not come to the front within 10 s of its launch (state \(app.state.rawValue))", file: file, line: line)
        } else if !el("step.cull").waitForExistence(timeout: 10) {
            Lumina.preconditionFailed("app never showed its step tabs", file: file, line: line)
        }
        return self
    }
    /// Quit and relaunch against the same store (decisions/edits must survive, R-70).
    func relaunch(file: StaticString = #filePath, line: UInt = #line) {
        guard !off else { return }
        app.terminate(); launch(file: file, line: line)
    }

    // MARK: elements
    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    func all(prefix: String) -> [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
    }
    func exists(_ id: String, timeout: TimeInterval = 0) -> Bool { off ? false : timeout > 0 ? el(id).waitForExistence(timeout: timeout) : el(id).exists }
    /// A status element's text: its value, or its label when the value is empty (`luminaStatus`
    /// sets both; on macOS a group element reports an empty value, so the label carries it).
    func value(_ id: String) -> String {
        guard !off else { return "" }
        let e = el(id)
        if let v = e.value as? String, !v.isEmpty { return v }
        return e.label
    }
    func click(_ id: String, times: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        guard !off else { return }
        let e = el(id); XCTAssertTrue(e.waitForExistence(timeout: 3), "missing \(id)", file: file, line: line)
        guard e.exists else { return }          // already failed above: clicking nothing would wait again
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
    /// What a stopped test reads instead of the app: nothing.
    private static let noState = try! JSONDecoder().decode(State.self, from: Data(
        #"{"step":"","copied":0,"total":0,"kept":0,"out":0,"undecided":0,"keep":{},"look":{},"looksCount":0,"lookBytes":0,"zoom":1,"errors":0}"#.utf8))
    var state: State {
        guard !off else { return Lumina.noState }
        let raw = value("debug.state")
        if let s = try? JSONDecoder().decode(State.self, from: Data(raw.utf8)) { return s }
        // The hook every check reads is gone (the app quit, or is not the native UI): not a crash of the runner.
        Lumina.preconditionFailed("debug.state unreadable: “\(raw.prefix(200))”")
        return Lumina.noState
    }
    struct Metrics: Decodable {
        struct Row: Decodable { let scene: Int; let width: Double; let gridWidth: Double; let last: Bool }
        let scale: Double; let minFontPt: Double; let bodyFontPt: Double; let fonts: [String: Double]
        let canvas: [Double]?; let photo: [Double]?; let tileH: Double?; let rows: [Row]?
    }
    var metrics: Metrics {
        let raw = off ? "" : value("debug.metrics")
        if let m = try? JSONDecoder().decode(Metrics.self, from: Data(raw.utf8)) { return m }
        Lumina.preconditionFailed("debug.metrics unreadable: “\(raw.prefix(200))”")
        return Metrics(scale: 1, minFontPt: 0, bodyFontPt: 0, fonts: [:], canvas: nil, photo: nil, tileH: nil, rows: nil)
    }

    func command(_ json: String, file: StaticString = #filePath, line: UInt = #line) {
        guard !off else { return }
        let f = el("debug.command")
        guard f.waitForExistence(timeout: 2) else { return Lumina.preconditionFailed("the debug.command hook is missing", file: file, line: line) }
        f.click(); f.typeText(json + "\r")
    }
    func resize(_ w: CGFloat, _ h: CGFloat, settle: TimeInterval = 0.25) { command("{\"resize\":[\(Int(w)),\(Int(h))]}"); pause(settle) }
    func blurWindow() { command("{\"blur\":true}") }

    // MARK: keys
    /// Never typed into nothing: a key sent while the app is not in front goes to whatever is
    /// (the user's own windows), or beeps.
    func key(_ k: String, _ mods: XCUIElement.KeyModifierFlags = [], file: StaticString = #filePath, line: UInt = #line) {
        guard !off else { return }
        guard app.state == .runningForeground else {
            return Lumina.preconditionFailed("the app is not in front (state \(app.state.rawValue)): the key would go to another app", file: file, line: line)
        }
        app.typeKey(k, modifierFlags: mods)
    }
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
    func pause(_ s: TimeInterval) { if !off { RunLoop.current.run(until: Date().addingTimeInterval(s)) } }
    @discardableResult func waitUntil(_ timeout: TimeInterval = 5, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end, !off { if cond() { return true }; pause(0.05) }
        return off ? false : cond()
    }
    func waitCopied(_ n: Int, timeout: TimeInterval = 15) -> Bool { waitUntil(timeout) { state.copied >= n } }

    // MARK: common flows
    func startCulling(waitAll: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        guard !off else { return }
        enter()
        // Three times what the copy should take at this card's rate, at least 8 s: a copy that
        // never started fails in seconds instead of a minute.
        let limit = max(8, 3 * Double(state.total) / Double(max(1, copyRate)))
        if waitAll, !waitCopied(state.total, timeout: limit) {
            return Lumina.preconditionFailed("copy never finished (\(state.copied) of \(state.total) after \(Int(limit)) s)", file: file, line: line)
        }
        pause(0.3)
    }
    func keepN(_ n: Int) { for _ in 0..<n { key("r"); pause(0.04) } }
    func importFixture(_ url: URL) { command("{\"drop\":[\"\(url.path)\"]}"); waitUntil(30) { !(state.import?.busy ?? false) } }

    // MARK: layout probes
    var window: XCUIElement { app.windows.firstMatch }
    func hasHorizontalScroll() -> Bool {
        let w = window.frame
        return app.scrollViews.allElementsBoundByIndex.contains { sv in
            sv.frame.width > w.width + 1 || sv.scrollBars.allElementsBoundByIndex.contains { $0.isHittable && $0.frame.width > $0.frame.height }
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
        guard TestGuard.stopped == nil else { return }       // the test was stopped: the app is gone, and that failure is recorded
        XCTAssertEqual(l.state.errors, 0, "R-73 unexpected errors", file: file, line: line)
    }
}
