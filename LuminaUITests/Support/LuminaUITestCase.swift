import Foundation
import XCTest

/// Common base for every Lumina UI test.
///
/// Responsibilities:
/// - Launch the app against isolated, deterministic fixture state.
/// - Expose the `LuminaRobot` façade and the structured state probe.
/// - On failure, preserve a full evidence bundle (screenshots, hierarchy, seed, trace, fixture,
///   persisted state snapshot, window size) so any failure is replayable without re-deriving it.
class LuminaUITestCase: XCTestCase {
    private(set) var app: XCUIApplication!
    private(set) var activeConfig: LaunchConfig?
    private(set) lazy var lumina = LuminaRobot(app: app, test: self)

    /// Human-readable action trace appended to by the explorer and flows; attached on failure.
    var trace: [String] = []

    override func setUp() {
        super.setUp()
        UITestWait.validateBudgetsOnLoad()
        continueAfterFailure = false
    }

    override func tearDown() {
        // Always terminate the app so instances never linger across tests (lingering instances make
        // the next launch's accessibility tree flaky).
        app?.terminate()
        // Clean up the isolated state directory unless the run failed (keep it for post-mortem).
        if let dir = activeConfig?.stateDirectory,
           testRun?.failureCount == 0,
           dir.path.contains("LuminaUITest") {
            try? FileManager.default.removeItem(at: dir)
        }
        app = nil
        super.tearDown()
    }

    // MARK: - Launch

    @discardableResult
    func launch(_ config: LaunchConfig) -> LuminaRobot {
        activeConfig = config
        app = launchUntilProbeAppears(config)
        lumina = LuminaRobot(app: app, test: self)
        record("launch fixture=\(config.fixture.rawValue) seed=\(config.seed)")
        return lumina
    }

    /// Launch the app and wait for the structured probe to appear, retrying once on a cold-start
    /// miss (occasionally the first launch of a fresh app process never fronts / renders under
    /// XCUITest — e.g. when the desktop session is in active interactive use and the new window
    /// loses activation). Self-healing keeps flows deterministic without arbitrary sleeps.
    ///
    /// If the probe never appears, this **fails the test immediately with diagnostics** instead of
    /// returning a terminated app handle. (Continuing used to cascade into minutes of dead element
    /// polling — 8 s + 40 s + 40 s nested waits against a process that no longer existed.)
    private func launchUntilProbeAppears(
        _ config: LaunchConfig,
        perAttemptTimeout: TimeInterval = UITestWait.launchAttempt
    ) -> XCUIApplication {
        var last = XCUIApplication()
        for attempt in 0..<2 {
            let application = XCUIApplication()
            application.launchArguments = config.launchArguments
            application.launch()
            application.activate()
            last = application
            let deadline = Date().addingTimeInterval(perAttemptTimeout)
            var nextActivation = Date().addingTimeInterval(5)
            while Date() < deadline {
                if application.probe() != nil { return application }
                // The app can lose activation to the interactive user mid-launch; a backgrounded
                // app exposes a collapsed accessibility tree. Re-front it periodically (bounded —
                // this adds no wait time of its own).
                if Date() >= nextActivation {
                    application.activate()
                    nextActivation = Date().addingTimeInterval(5)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
            record("launch attempt \(attempt) saw no probe; retrying")
            application.terminate()
        }
        XCTFail(
            """
            state probe never appeared after 2 launch attempts of \(Int(perAttemptTimeout))s each — \
            the app's window/accessibility tree did not mount (is the desktop session busy?).
            probe route: \(last.probe()?.route ?? "<no probe>")
            app state: \(last.state.rawValue) (4 = runningForeground)
            state root: \(config.stateDirectory.path)
            seeded shoots: \(OpenShootRobot.seededShoots(in: config.stateDirectory))
            launch args: \(config.launchArguments.joined(separator: " "))
            accessibility excerpt:
            \(String(last.debugDescription.prefix(1_500)))
            """
        )
        return last
    }

    /// Terminate and relaunch against the same state directory (persistence / relaunch flows).
    @discardableResult
    func relaunch() -> LuminaRobot {
        guard let config = activeConfig else {
            XCTFail("relaunch() called before launch()")
            return lumina
        }
        app.terminate()
        return launch(config.relaunch())
    }

    // MARK: - Trace

    func record(_ step: String) {
        trace.append(step)
    }

    // MARK: - Diagnostics

    lazy var diagnostics = DiagnosticsRobot(app: app, test: self)

    override func record(_ issue: XCTIssue) {
        // Capture evidence at the moment of failure, before app state moves on.
        if app != nil {
            DiagnosticsRobot(app: app, test: self)
                .captureFailureEvidence(reason: issue.compactDescription, context: diagnosticContext())
            if let dir = activeConfig?.stateDirectory {
                let shoot = dir
                    .appendingPathComponent("Lumina/projects/\(activeConfig!.fixture.rawValue)/shoot.json")
                DiagnosticsRobot(app: app, test: self)
                    .attachFileIfPresent(name: "persisted-shoot.json", url: shoot)
            }
        }
        super.record(issue)
    }

    /// Structured context recorded with every failure.
    func diagnosticContext() -> [String: String] {
        var ctx: [String: String] = [:]
        if let config = activeConfig {
            ctx["fixture"] = config.fixture.rawValue
            ctx["seed"] = String(config.seed)
            ctx["stateDirectory"] = config.stateDirectory.path
            ctx["launchArguments"] = config.launchArguments.joined(separator: " ")
        }
        let window = app.windows.firstMatch
        if window.exists {
            let frame = window.frame
            ctx["windowSize"] = "\(Int(frame.width))x\(Int(frame.height))"
        }
        ctx["traceCount"] = String(trace.count)
        ctx["trace"] = trace.joined(separator: "\n")
        return ctx
    }
}
