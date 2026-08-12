import Foundation
import XCTest

/// Named deterministic fixtures the app can seed. Mirrors `UITestFixtures.specs`.
enum Fixture: String {
    case mixed60 = "mixed-60"
    case mixed200 = "mixed-200"
    case missingOriginals = "missing-originals"
}

/// Environment overrides supplied by `Scripts/run/run_p0_ui_tests.sh` (or Xcode) so a single test can
/// be scaled or replayed without editing code.
enum TestEnv {
    static var seed: UInt64? {
        ProcessInfo.processInfo.environment["LUMINA_UI_TEST_SEED"].flatMap(UInt64.init)
    }
    static var steps: Int? {
        ProcessInfo.processInfo.environment["LUMINA_UI_TEST_STEPS"].flatMap(Int.init)
    }
    /// Root under which per-test isolated state directories are created. Defaults to the system
    /// temp dir; the runner points this at a documented artifact directory.
    static var stateRoot: URL {
        if let path = ProcessInfo.processInfo.environment["LUMINA_UI_TEST_STATE_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("LuminaUITestState", isDirectory: true)
    }
}

/// Describes how to launch the app under test against isolated deterministic state.
struct LaunchConfig {
    var fixture: Fixture
    var seed: UInt64
    /// Reused across relaunches when persistence must be observed. A fresh directory means a clean
    /// launch; the same directory means "relaunch against the same state".
    var stateDirectory: URL
    var reduceMotion: Bool
    var reset: Bool
    /// Pinned content size, or nil to let the app size itself.
    var windowSize: CGSize?
    /// Open the fixture on launch through the real openRecent path (default). Set false to test the
    /// manual Open-surface click-through.
    var autoOpen: Bool

    init(
        fixture: Fixture,
        seed: UInt64 = 84_721,
        stateDirectory: URL? = nil,
        reduceMotion: Bool = true,
        reset: Bool = false,
        windowSize: CGSize? = nil,
        autoOpen: Bool = true
    ) {
        self.fixture = fixture
        self.seed = TestEnv.seed ?? seed
        self.stateDirectory = stateDirectory
            ?? TestEnv.stateRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.reduceMotion = reduceMotion
        self.reset = reset
        self.windowSize = windowSize
        self.autoOpen = autoOpen
    }

    var launchArguments: [String] {
        var args = [
            "--ui-testing",
            "--fixture-shoot", fixture.rawValue,
            "--ui-test-state-directory", stateDirectory.path,
            "--ui-test-seed", String(seed),
        ]
        if reduceMotion { args.append("--reduce-motion") }
        if reset { args.append("--ui-test-reset") }
        if autoOpen { args.append("--ui-test-autoopen") }
        if let windowSize {
            args.append(contentsOf: ["--ui-test-window", "\(Int(windowSize.width))x\(Int(windowSize.height))"])
        }
        return args
    }

    /// A config that reuses this state directory (for relaunch/persistence tests).
    func relaunch(reset: Bool = false) -> LaunchConfig {
        var copy = self
        copy.reset = reset
        return copy
    }
}
