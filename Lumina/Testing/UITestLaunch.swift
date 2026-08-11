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

        UITestSupport.isActive = true
        UITestSupport.seed = UITestSupport.seedValue()
        UITestSupport.reduceMotionForced = UITestSupport.reduceMotionRequested()
        UITestSupport.forcedWindowSize = UITestSupport.windowSize()
        UITestSupport.autoOpen = UITestSupport.autoOpenRequested()

        let stateDir = UITestSupport.stateDirectory() ?? makeUniqueTemporaryStateDirectory()
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        UITestSupport.stateDirectoryOverride = stateDir

        let fixture = UITestSupport.fixture()
        UITestSupport.fixtureName = fixture
        let opened = UITestFixtures.ensure(named: fixture, reset: UITestSupport.resetRequested())

        // Probe v2 + fake clock — DEBUG harness only; never present in Release.
        HarnessFakeClock.reset()
        ProbeV2Launch.runIfRequested()

        fputs(
            "[UITestLaunch] ui-testing active · fixture=\(opened ?? "none") · seed=\(UITestSupport.seed) · state=\(stateDir.path)\n",
            stderr
        )
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
}
#endif
