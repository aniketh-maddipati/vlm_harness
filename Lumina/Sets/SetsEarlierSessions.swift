import Foundation

/// Sessions from before the sandbox (release task R1e): the words of the launch question and its
/// folder panel, in one place, and where the earlier build kept its files. The import itself is
/// `SetsShootStore.importStore`; the alert and the panel are in `SetsRootView.swift`. The wording
/// is handed to the design in DESIGN-ASKS ("sessions from before the sandbox").
nonisolated enum SetsEarlierSessions {
    static let message = "Bring over your earlier sessions?"
    static let detail = "Lumina now keeps its working files in a protected place of its own. If you used an earlier version on this Mac, choose its folder and Lumina brings your decisions over. Photos and sidecars stay where they are."
    static let choose = "Choose Folder…"
    static let notNow = "Not Now"

    static let panelPrompt = "Bring Over"
    static let panelMessage = "Choose the folder “Lumina” in Library ▸ Application Support. Lumina only reads it."
    static let panelRefusal = "No earlier sessions in that folder. Choose “Lumina” in Library ▸ Application Support of your home folder."

    /// A recent that came over without its bookmark, picked in File ▸ Open Recent.
    static let recentNeedsFolder = "not available yet · open its folder once with ⌘O"
    static func failed(_ why: String) -> String { "earlier sessions not brought over · \(why)" }

    /// The user's real home folder. In a sandboxed process `NSHomeDirectory()` is the container.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// Where every build before the sandbox kept its working files. Only ever handed to the
    /// panel as the place to start: the app reads it after the user picked it there, not before.
    static var earlierSupportDir: URL {
        realHome.appendingPathComponent("Library/Application Support/Lumina", isDirectory: true)
    }

    /// The logic tests are hosted in the app: a launch under XCTest never asks.
    static var underTest: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
}
