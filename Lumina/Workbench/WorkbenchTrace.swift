#if DEBUG
import Foundation
import os

/// One-line trace for the workbench boot, so a polish session that lands on nothing says why
/// instead of leaving the operator staring at an empty table.
///
/// Writes to both stderr (visible when the binary is run straight from a terminal) and the
/// unified log (visible when LaunchServices swallows stderr):
///   /usr/bin/log stream --predicate 'subsystem == "com.lumina.workbench"' --level debug
enum WorkbenchTrace {
    static let subsystem = "com.lumina.workbench"
    private static let logger = Logger(subsystem: subsystem, category: "boot")

    static func log(_ message: @autoclosure () -> String) {
        let text = message()
        fputs("[Workbench] \(text)\n", stderr)
        logger.notice("\(text, privacy: .public)")
    }
}
#endif
