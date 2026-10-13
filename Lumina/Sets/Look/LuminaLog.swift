import os

/// The app's log (release task R7, docs/release/TRUST.md I8). File and folder names, paths and
/// error texts (which can hold a path) go in as private, so `log show` and a sysdiagnose show
/// `<private>` for them; counts, versions and op names are public. Nothing else in the app logs:
/// Scripts/trust_check.py refuses NSLog and print.
nonisolated enum LuminaLog {
    static let subsystem = "com.aniketh.lumina"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let canvas = Logger(subsystem: subsystem, category: "canvas")
    static let export = Logger(subsystem: subsystem, category: "export")
}
