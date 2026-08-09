import Foundation

/// Propagation ring for staged copy — row → scene → shoot.
enum PropagationRing: Equatable {
    case row
    case scene
    case shoot
}

/// ONE count source for banner, header, and receipt (A1 invariant).
struct StagingCopySnapshot: Equatable {
    var scopeCount: Int
    var excludedCount: Int = 0
    var rowIndex: Int = 1
    var laneTimestamp: String = "18:17"
    var referenceFrameNumber: String = "8288"
    var ring: PropagationRing = .row
    var isDevelop: Bool = false

    /// Committed count shown in header, banner, and receipt — must stay aligned (A1).
    var a1Count: Int { scopeCount }
}

enum A1Invariant {
    /// Extract the primary scope count from staged header, banner, or receipt copy.
    static func committedCount(in text: String) -> Int? {
        if let match = text.range(of: #"Adapted → (\d+)"#, options: .regularExpression) {
            let slice = text[match].dropFirst("Adapted → ".count)
            return Int(slice.prefix(while: { $0.isNumber }))
        }
        if let match = text.range(of: #"Adapt → (\d+)"#, options: .regularExpression) {
            let slice = text[match].dropFirst("Adapt → ".count)
            return Int(slice.prefix(while: { $0.isNumber }))
        }
        if let match = text.range(of: #"Develop → (\d+)"#, options: .regularExpression) {
            let slice = text[match].dropFirst("Develop → ".count)
            return Int(slice.prefix(while: { $0.isNumber }))
        }
        if let match = text.range(of: #"· (\d+) selected"#, options: .regularExpression) {
            let digits = text[match].filter(\.isNumber)
            return Int(digits)
        }
        return nil
    }

    static func excludedCount(in text: String) -> Int? {
        guard let match = text.range(of: #"(\d+) excluded"#, options: .regularExpression) else { return nil }
        let digits = text[match].filter(\.isNumber)
        return Int(digits)
    }

    /// Banner, header, and receipt must agree on scope count (and exclusions when present).
    static func validate(header: String, banner: String, receipt: String, snapshot: StagingCopySnapshot) -> Bool {
        guard let headerCount = committedCount(in: header), headerCount == snapshot.a1Count else { return false }
        guard let bannerCount = committedCount(in: banner), bannerCount == snapshot.a1Count else { return false }
        guard let receiptCount = committedCount(in: receipt), receiptCount == snapshot.a1Count else { return false }
        if snapshot.excludedCount > 0 {
            guard excludedCount(in: header) == snapshot.excludedCount else { return false }
            guard excludedCount(in: banner) == snapshot.excludedCount else { return false }
        }
        return true
    }
}
