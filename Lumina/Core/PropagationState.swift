import Foundation

/// Wholesale propagation scope — row → scene → shoot concentric rings (hi-fi H6).
struct PropagationState: Equatable, Sendable {
    var ring: PropagationRing = .row
    var referencePhotoID: AssetID
    var referenceGroupID: String
    var referenceFrame: String
    /// Shoot-persisted hand exclusions — survive re-staging and relaunch.
    var excludedIDs: Set<AssetID> = []

    /// Widen exactly one ring. Returns false when already at shoot.
    mutating func widen() -> Bool {
        switch ring {
        case .row: ring = .scene; return true
        case .scene: ring = .shoot; return true
        case .shoot: return false
        }
    }

    /// Narrow exactly one ring. Returns false at row (caller cancels whole stage).
    mutating func narrow() -> Bool {
        switch ring {
        case .shoot: ring = .scene; return true
        case .scene: ring = .row; return true
        case .row: return false
        }
    }
}
