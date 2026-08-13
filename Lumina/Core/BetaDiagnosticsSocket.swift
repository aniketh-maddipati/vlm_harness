import Foundation

/// D45 / R-9.1 diagnostics socket — must remain absent on wave and launch builds.
///
/// Wave builds: `activeKind` is `nil` (local-only / absent diagnostics per D45/A13).
/// A7 (TestFlight crash reporting) was withdrawn; enabling any non-nil kind requires an
/// explicit future amendment — F11.6 fails if this socket or manifest `betaDiagnostics`
/// is non-null.
enum BetaDiagnosticsSocket {
    /// Active beta diagnostics kind, or `nil` when absent (wave / launch default).
    static let activeKind: String? = nil
}
