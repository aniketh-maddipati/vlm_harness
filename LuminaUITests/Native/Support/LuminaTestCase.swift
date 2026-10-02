import XCTest
import AppKit

/// What every UI suite inherits, so that a test ends, runs alone, and leaves nothing behind
/// (AGENTS.md, "Running tests without disturbing the Mac"):
///
/// - a wall-clock limit per test, enforced by a watchdog, not by the test: at the limit the app
///   is quit, the helpers in `Lumina` stop doing anything, the test fails with the limit named,
///   and 30 s later the runner itself exits if the test is still there;
/// - a broken precondition (the app did not launch, is not in front, the copy never finished)
///   fails once and ends the test, instead of every later assertion waiting its turn;
/// - the screen lock (`~/LuminaEvidence/.screen.lock`): a second screen-owning run is refused;
/// - a refusal while the user's own Lumina is open: launching the test build would quit it;
/// - whatever a test launched is quit and its store folder removed, pass or fail.
class LuminaTestCase: XCTestCase {
    /// Seconds one test of this class may take, setUp to tearDown (four times that with
    /// LUMINA_LONG=1, where the loops are longer; LUMINA_TEST_LIMIT=<s> sets it for a run).
    class var limit: TimeInterval { 120 }
    /// A suite that is only run on purpose (LUMINA_LONG=1): Load, Soak.
    class var long: Bool { false }

    override func setUpWithError() throws {
        try XCTSkipIf(Self.long && !Lumina.long, "a long suite, run on purpose: LUMINA_LONG=1 bash Scripts/test.sh ui \(Self.self)")
    }

    override func invokeTest() {
        Lumina.begin(self)
        if let why = TestGuard.refusal {
            record(XCTIssue(type: .assertionFailure, compactDescription: why))
            return
        }
        let asked = ProcessInfo.processInfo.environment["LUMINA_TEST_LIMIT"].flatMap(TimeInterval.init)
        TestGuard.arm(asked ?? Self.limit * (Lumina.long ? 4 : 1), test: name)
        super.invokeTest()
        if let why = TestGuard.disarm() { record(XCTIssue(type: .assertionFailure, compactDescription: why)) }
        Lumina.endAll()
        Fixtures.removeAll()
    }
}

/// The parts that run off the main thread or once per runner. Thread-safe; touches no XCUI object.
nonisolated enum TestGuard {
    static let appID = "com.lumina.app"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var why: String?
    nonisolated(unsafe) private static var timedOut: String?
    nonisolated(unsafe) private static var timers: [DispatchSourceTimer] = []
    nonisolated(unsafe) private static var screenFD: Int32 = -1

    /// Set when the test must not go on (a failed precondition, the limit): `Lumina`'s helpers
    /// return at once from then on.
    static var stopped: String? { lock.lock(); defer { lock.unlock() }; return why }
    static func stop(_ reason: String) { lock.lock(); if why == nil { why = reason }; lock.unlock() }

    /// Checked once per runner. Nil, or why no UI test may run on this Mac right now.
    static let refusal: String? = {
        if let mine = NSRunningApplication.runningApplications(withBundleIdentifier: appID).first(where: { !isTestBuild($0) }) {
            return "REFUSED: Lumina is open (\(mine.bundleURL?.path ?? "?")): a UI test would quit it and take its place. Quit it, then run the tests."
        }
        let home = String(cString: getpwuid(getuid()).pointee.pw_dir)
        let dir = ProcessInfo.processInfo.environment["LUMINA_GUARD_DIR"] ?? home + "/LuminaEvidence"
        // The kill switch (Scripts/stop_tests.sh --off): nothing starts while it is there.
        if FileManager.default.fileExists(atPath: dir + "/.tests-off") {
            return "REFUSED: tests are switched off on this Mac (\(dir)/.tests-off). Only the user turns them back on: bash Scripts/stop_tests.sh --on"
        }
        guard ProcessInfo.processInfo.environment["LUMINA_SCREEN_LOCK_HELD"] == nil else { return nil }     // Scripts/test.sh holds it
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/.screen.lock"
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return nil }           // a sandboxed runner cannot reach it: nothing to enforce with
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let who = FileManager.default.contents(atPath: path).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
            return "REFUSED: the screen is in use by another test run: \(who). One at a time; `bash Scripts/stop_tests.sh` stops it."
        }
        let record = "{\"pid\": \(getpid()), \"name\": \"LuminaUITests (run from Xcode)\", \"since\": \"\(Date())\"}"
        ftruncate(fd, 0); _ = record.withCString { write(fd, $0, strlen($0)) }
        screenFD = fd               // held until the runner exits
        return nil
    }()

    static func isTestBuild(_ app: NSRunningApplication) -> Bool {
        let path = app.bundleURL?.path ?? ""
        return !path.hasPrefix("/Applications/") && !path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// Quits the app under test without XCUI (usable from any thread). Never the installed app.
    static func killApp() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: appID) where isTestBuild(app) { app.forceTerminate() }
    }

    static func arm(_ limit: TimeInterval, test: String) {
        lock.lock(); why = nil; timedOut = nil; lock.unlock()
        let soft = DispatchSource.makeTimerSource(queue: .global())
        soft.schedule(deadline: .now() + limit)
        soft.setEventHandler {
            let text = "\(test) reached its limit of \(Int(limit)) s and was stopped (LuminaTestCase.limit; LUMINA_TEST_LIMIT=<s> changes it for a run)"
            lock.lock(); timedOut = text; if why == nil { why = text }; lock.unlock()
            killApp()
        }
        let hard = DispatchSource.makeTimerSource(queue: .global())
        hard.schedule(deadline: .now() + limit + 30)
        hard.setEventHandler {
            fputs("FAIL  \(test) was still running 30 s after its limit of \(Int(limit)) s: the test runner exits\n", stderr)
            killApp()
            exit(70)
        }
        soft.resume(); hard.resume()
        lock.lock(); timers = [soft, hard]; lock.unlock()
    }

    /// Ends the watch. Returns the limit's message if the test ran into it.
    static func disarm() -> String? {
        lock.lock(); defer { lock.unlock() }
        timers.forEach { $0.cancel() }; timers = []
        return timedOut
    }
}
