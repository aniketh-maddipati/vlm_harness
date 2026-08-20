#if DEBUG
import Foundation

/// DEBUG-only entry point that puts the app into UI-test mode before the first scene appears.
///
/// Invoked once from `LuminaApp.init()`. When the `--ui-testing` argument (or `LUMINA_UI_TEST_MODE`
/// environment variable) is present it:
///   1. Redirects all persistence into an isolated state directory (never the real catalog).
///   2. Seeds the requested deterministic fixture shoot.
///   3. Records seed / reduce-motion so the running app is deterministic.
///
/// It deliberately does **not** navigate anywhere — the harness opens the shoot through the real
/// Open UI so the actual routing, command and persistence paths are exercised end to end.
///
/// This whole file is compiled out of Release, so there is no test-only entry point in a shipping
/// build.
@MainActor
enum UITestLaunch {
    static func runIfRequested() {
        guard UITestSupport.requested() else { return }
        let launchStart = monotonicMilliseconds()
        log("runIfRequested.enter t=\(launchStart)")

        UITestSupport.isActive = true
        UITestSupport.seed = UITestSupport.seedValue()
        UITestSupport.reduceMotionForced = UITestSupport.reduceMotionRequested()
        UITestSupport.forcedWindowSize = UITestSupport.windowSize()
        UITestSupport.autoOpen = UITestSupport.autoOpenRequested()

        let providedStateDir = UITestSupport.stateDirectory()
        let stateDir = providedStateDir ?? makeUniqueTemporaryStateDirectory()
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        UITestSupport.stateDirectoryOverride = stateDir

        let fixture = UITestSupport.fixture()
        UITestSupport.fixtureName = fixture
        let ensureStart = monotonicMilliseconds()
        log(
            """
            ensure.enter fixture=\(fixture) stateDirSource=\(providedStateDir == nil ? "generated" : "launch-arg") \
            state=\(stateDir.path) t=\(ensureStart)
            """
        )
        let opened = UITestFixtures.ensure(named: fixture, reset: UITestSupport.resetRequested())
        let ensureEnd = monotonicMilliseconds()
        log(
            "ensure.exit fixture=\(fixture) opened=\(opened ?? "none") elapsedMs=\(ensureEnd - ensureStart) t=\(ensureEnd)"
        )

        // Probe v2 + fake clock — DEBUG harness only; never present in Release.
        HarnessFakeClock.reset()
        ProbeV2Launch.runIfRequested()

        let launchEnd = monotonicMilliseconds()
        fputs(
            "[UITestLaunch] ui-testing active · fixture=\(opened ?? "none") · seed=\(UITestSupport.seed) · state=\(stateDir.path) · elapsedMs=\(launchEnd - launchStart)\n",
            stderr
        )
        log("runIfRequested.exit fixture=\(fixture) elapsedMs=\(launchEnd - launchStart) t=\(launchEnd)")
    }

    /// Unique per-launch temporary directory used when the harness does not supply one.
    /// The harness normally passes `--ui-test-state-directory`, but a stand-alone launch stays
    /// isolated regardless.
    private static func makeUniqueTemporaryStateDirectory() -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LuminaUITest", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return base
    }

    private static func monotonicMilliseconds() -> Int {
        Int((ProcessInfo.processInfo.systemUptime * 1_000.0).rounded())
    }

    private static func log(_ message: String) {
        appendTimingLogLine("[UITestLaunchTiming] \(message)")
    }

    private static func appendTimingLogLine(_ line: String) {
        let fullLine = "\(line)\n"
        fputs(fullLine, stderr)
        guard let stateDir = UITestSupport.stateDirectoryOverride else { return }
        let url = stateDir.appendingPathComponent("launch-timing.log")
        let data = Data(fullLine.utf8)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
#endif
