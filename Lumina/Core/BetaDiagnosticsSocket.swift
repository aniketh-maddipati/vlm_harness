import Foundation

/// A7 / D45 beta diagnostics socket — TestFlight crash reporting exception only.
///
/// Wave builds: `activeKind` is `nil` (local-only / absent diagnostics).
/// When a beta distribution enables TestFlight crash reporting, set `activeKind` and
/// ensure `LuminaBuildManifest` records `betaDiagnostics` with `expiresAtMarketingVersion: "1.0"`.
/// F11.6 fails if marketing version ≥ 1.0 while this socket is still active.
enum BetaDiagnosticsSocket {
    /// Contract token value when beta TestFlight reporting is enabled.
    static let testFlightCrashReportingKind = "testflight_crash_reporting"

    /// Active beta diagnostics kind, or `nil` when absent (wave / launch default).
    static let activeKind: String? = nil
}
