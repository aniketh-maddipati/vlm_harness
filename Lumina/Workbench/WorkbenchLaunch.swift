#if DEBUG
import Foundation

/// DEBUG-only workbench activation: decides whether this launch is a polish session, resolves
/// the requested latency card against `FIXTURE_ROOT`, and remembers the deep-link so a relaunch
/// lands on the same surface.
///
/// Mirrors the shape of `UITestLaunch` deliberately — one auditable place that answers
/// "am I a workbench launch, and which photographs am I pointed at?".
///
/// Compiled out of Release entirely. Within DEBUG it is still inert unless `--workbench` is
/// passed; Lumina Debug defines `LUMINA_WORKBENCH` for Inject + `.workbenchHot()`.
@MainActor
enum WorkbenchLaunch {
    static let flag = "--workbench"
    static let offFlag = "--no-workbench"

    /// Workbench boot is opt-in via `--workbench`; hot reload is always on in Debug.
    nonisolated static var defaultOn: Bool { false }

    /// Resolved state for this launch. `nil` until `runIfRequested()` has run.
    nonisolated(unsafe) static private(set) var boot: WorkbenchBootPlan?

    static func requested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaultOn: Bool = WorkbenchLaunch.defaultOn
    ) -> Bool {
        if arguments.contains(offFlag) { return false }
        if arguments.contains(flag) { return true }
        return defaultOn
    }

    /// Root holding the cut latency cards. Honors `FIXTURE_ROOT` / `LUMINA_FIXTURE_ROOT`;
    /// otherwise the location E1 cut them to.
    static func fixtureRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        for key in ["LUMINA_FIXTURE_ROOT", "FIXTURE_ROOT"] {
            if let value = environment[key], !value.isEmpty {
                return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/lumina-fixtures", isDirectory: true)
    }

    /// Builds the plan for this launch without touching the session, so it is unit-testable.
    static func plan(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (URL) -> Bool = { url in
            var isDirectory: ObjCBool = false
            let ok = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return ok && isDirectory.boolValue
        }
    ) -> WorkbenchBootPlan {
        var (link, unresolved) = WorkbenchDeepLink.parse(arguments: arguments)

        // A relaunch with no surface named restores the last one an operator looked at.
        if !arguments.contains(WorkbenchDeepLink.cardFlag), let remembered = restoreLink() {
            link = remembered
        }

        if link.surface == .loupe {
            unresolved.append("--surface loupe has no referent in P0 yet — landed on frame")
        }

        let root = fixtureRoot(environment: environment)
        let card = root.appendingPathComponent(link.card, isDirectory: true)
        return WorkbenchBootPlan(
            link: link,
            fixtureRoot: root,
            card: card,
            cardExists: fileExists(card),
            unresolved: unresolved
        )
    }

    /// Called once from `LuminaApp.init()`, before any scene appears.
    static func runIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        // The UI-test harness owns launch when both are present; never fight it for the session.
        guard requested(arguments: arguments), !UITestSupport.requested(arguments: arguments) else { return }

        let plan = plan(arguments: arguments, environment: environment)
        boot = plan
        rememberLink(plan.link)

        fputs(
            "[WorkbenchLaunch] card=\(plan.link.card) surface=\(plan.link.surface.rawValue) "
                + "row=\(plan.link.row.map(String.init) ?? "-") focused=\(plan.link.focused) "
                + "exists=\(plan.cardExists) path=\(plan.card.path)\n",
            stderr
        )
    }

    // MARK: - Deep-link memory (Gate 2.3)

    private static let rememberedKey = "lumina.workbench.lastDeepLink"

    private static func rememberLink(_ link: WorkbenchDeepLink) {
        UserDefaults.standard.set(link.arguments, forKey: rememberedKey)
    }

    private static func restoreLink() -> WorkbenchDeepLink? {
        guard let stored = UserDefaults.standard.stringArray(forKey: rememberedKey) else { return nil }
        return WorkbenchDeepLink.parse(arguments: stored).link
    }

    /// Test seam — drops the remembered deep-link.
    static func forgetLink() {
        UserDefaults.standard.removeObject(forKey: rememberedKey)
    }
}

/// Everything the boot needs, resolved once at launch.
struct WorkbenchBootPlan: Equatable {
    var link: WorkbenchDeepLink
    var fixtureRoot: URL
    var card: URL
    var cardExists: Bool
    /// Human-readable notes about arguments that could not be honored. Never fatal.
    var unresolved: [String]
}
#endif
