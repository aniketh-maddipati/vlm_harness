import Foundation
import Observation

// WP-6. The overlays' own state (the contract's `EditState` holds what other work packages and
// `debug.state` read: `overlay`, `variationKey`, `variationIndex`, `variationSticky`,
// `variationPhoto`). Reached with `model.overlays`.

@MainActor @Observable
public final class OverlayState {
    /// The open Variations grid's cells. Nil when the grid is closed.
    public internal(set) var spec: VariationSpec?
    /// V is still down since it opened the grid ("let go of V to apply").
    public internal(set) var held = false
    /// The highlighted cell has been chosen and lands when the 120 ms window ends (R-06).
    public internal(set) var applying = false

    /// When the V that opened the grid went down; nil once it is released or the grid closed.
    @ObservationIgnored var vDownAt: Date?
    @ObservationIgnored var pendingApply: ScheduledWork?
    /// Counts opens, so a timer from an earlier grid never acts on a later one.
    @ObservationIgnored var generation = 0

    /// The intro has been offered in this window (once per launch, even when forced).
    @ObservationIgnored var introOffered = false
    /// Where "the intro has been seen" is kept (the prototype's `lumina.edit.intro.v1`).
    @ObservationIgnored public var intro: IntroFlag
    /// `LUMINA_INTRO=show`: show it on the first visit to Edit even if it was seen before.
    @ObservationIgnored public var introForced: Bool

    @ObservationIgnored var toastTimer: ScheduledWork?

    public init(config: LaunchConfig) {
        // A UI-test launch without a store directory must not touch the user's defaults.
        intro = config.uiTest && config.storeDir == nil ? .memory() : IntroFlag(storeDir: config.storeDir)
        // `LaunchConfig` only carries `skipIntro` (CONTRACT-REQUESTS/WP6.md): read "show" from the environment.
        introForced = !config.skipIntro && ProcessInfo.processInfo.environment["LUMINA_INTRO"] == "show"
    }
}

/// The first-run flag. With a store directory (tests, `LUMINA_STORE_DIR`) it is a marker file
/// in that directory, so a test never reads or writes the user's defaults; otherwise it is the
/// app's UserDefaults.
public struct IntroFlag {
    public static let key = "lumina.edit.intro.v1"
    public var read: () -> Bool
    public var write: (Bool) -> Void

    public init(read: @escaping () -> Bool, write: @escaping (Bool) -> Void) { self.read = read; self.write = write }

    public init(storeDir: URL?, defaults: UserDefaults = .standard) {
        if let dir = storeDir {
            let file = dir.appendingPathComponent(Self.key)
            read = { FileManager.default.fileExists(atPath: file.path) }
            write = { seen in
                if seen {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    // If this fails (disk full) the intro simply shows again next time.
                    _ = FileManager.default.createFile(atPath: file.path, contents: Data("1".utf8))
                } else { try? FileManager.default.removeItem(at: file) }
            }
        } else {
            read = { defaults.bool(forKey: Self.key) }
            write = { defaults.set($0, forKey: Self.key) }
        }
    }

    /// Kept in memory only (tests).
    public static func memory(seen: Bool = false) -> IntroFlag {
        final class Box { var seen: Bool; init(_ s: Bool) { seen = s } }
        let b = Box(seen)
        return IntroFlag(read: { b.seen }, write: { b.seen = $0 })
    }

    public var seen: Bool { get { read() } nonmutating set { write(newValue) } }
}

public extension AppModel {
    var overlays: OverlayState { feature(OverlayState.self) { OverlayState(config: config) } }
}
