import Foundation

/// Runtime hooks that the shipping app honors when it is driven by the XCUITest harness.
///
/// This type is **always compiled** (it is read from `ShootStore` and the P0 views), but it is
/// only ever *activated* by the DEBUG-only `UITestLaunch` entry point. In a Release build nothing
/// sets `isActive` or `stateDirectoryOverride`, so every accessor below returns its inert default
/// and the app behaves exactly as it always has. There is no test-only behavior in Release.
///
/// Design goals:
/// - Never read or mutate the maintainer's real `~/Library/Application Support/Lumina` state.
/// - Give the app a single, auditable place to answer "am I under UI test, and where is my state?".
enum UITestSupport {
    // MARK: - Activation state (set once, at launch, before any concurrency)

    /// True when the app was launched by the UI-test harness (DEBUG only).
    nonisolated(unsafe) static var isActive = false

    /// Isolated Application Support root the app must use instead of the real one.
    /// `ShootStore.supportDirectory()` appends `Lumina/` to this when set.
    nonisolated(unsafe) static var stateDirectoryOverride: URL?

    /// Forces reduced-motion behavior regardless of the system accessibility setting,
    /// so animation timing never makes UI tests flaky.
    nonisolated(unsafe) static var reduceMotionForced = false

    /// Deterministic seed forwarded from the harness. The app does not consume it directly
    /// (the explorer does), but it is exposed on the state probe for evidence capture.
    nonisolated(unsafe) static var seed: UInt64 = 0

    /// Name of the fixture shoot seeded for this launch (e.g. `mixed-60`).
    nonisolated(unsafe) static var fixtureName: String?

    /// Exact content size the harness pinned for this launch (visual / layout determinism).
    nonisolated(unsafe) static var forcedWindowSize: CGSize?

    /// When true, the app opens the seeded fixture shoot on appear via the real `openRecent` path.
    /// Lets most flows skip the flaky SwiftUI Open-surface accessibility while still exercising the
    /// real open/command/persistence path. The manual click-through is covered by its own test.
    nonisolated(unsafe) static var autoOpen = false

    // MARK: - Launch-argument / environment parsing (pure)

    static let modeFlag = "--ui-testing"
    static let fixtureFlag = "--fixture-shoot"
    static let stateDirFlag = "--ui-test-state-directory"
    static let seedFlag = "--ui-test-seed"
    static let reduceMotionFlag = "--reduce-motion"
    static let resetFlag = "--ui-test-reset"
    static let windowFlag = "--ui-test-window"
    static let autoOpenFlag = "--ui-test-autoopen"

    static func autoOpenRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        arguments.contains(autoOpenFlag) || environment["LUMINA_UI_TEST_AUTOOPEN"] == "1"
    }

    /// Whether either the `--ui-testing` argument or `LUMINA_UI_TEST_MODE=1` is present.
    static func requested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if arguments.contains(modeFlag) { return true }
        if let value = environment["LUMINA_UI_TEST_MODE"], value == "1" || value.lowercased() == "true" {
            return true
        }
        return false
    }

    static func fixture(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let value = flagValue(fixtureFlag, in: arguments) { return value }
        if let value = environment["LUMINA_UI_TEST_FIXTURE"], !value.isEmpty { return value }
        return "mixed-60"
    }

    static func stateDirectory(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let value = flagValue(stateDirFlag, in: arguments), !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        if let value = environment["LUMINA_UI_TEST_STATE_DIR"], !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return nil
    }

    static func seedValue(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UInt64 {
        if let value = flagValue(seedFlag, in: arguments), let seed = UInt64(value) { return seed }
        if let value = environment["LUMINA_UI_TEST_SEED"], let seed = UInt64(value) { return seed }
        return 0
    }

    static func reduceMotionRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if arguments.contains(reduceMotionFlag) { return true }
        if let value = environment["LUMINA_UI_TEST_REDUCE_MOTION"], value == "1" { return true }
        return false
    }

    static func resetRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if arguments.contains(resetFlag) { return true }
        if let value = environment["LUMINA_UI_TEST_RESET"], value == "1" { return true }
        return false
    }

    /// Parse `--ui-test-window 1280x800` (or `LUMINA_UI_TEST_WINDOW`) into a size.
    static func windowSize(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CGSize? {
        let raw = flagValue(windowFlag, in: arguments) ?? environment["LUMINA_UI_TEST_WINDOW"]
        guard let raw else { return nil }
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Value that follows `flag` in an argument list (`--flag value`), when the next token
    /// is not itself a flag. Returns nil when absent.
    static func flagValue(_ flag: String, in arguments: [String]) -> String? {
        guard let idx = arguments.firstIndex(of: flag),
              arguments.indices.contains(idx + 1) else { return nil }
        let next = arguments[idx + 1]
        return next.hasPrefix("--") ? nil : next
    }
}
