import Foundation

// MARK: - Job brief (Phase C)

struct JobBrief: Codable, Equatable {
    var targetKeepCount: Int?
    var keepRate: Double = 0.10
    var eventType: EventType = .general
    var autoDeliver: Bool = false
    var confidenceThreshold: Double = 0.72
    var deliveryAspects: [ExportAspect] = [.fourByFive, .nineBySixteen]

    enum EventType: String, Codable, CaseIterable, Identifiable {
        case general, wedding, portrait, event
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general: "General"
            case .wedding: "Wedding"
            case .portrait: "Portrait"
            case .event: "Event"
            }
        }
    }

    func resolvedKeepRate(totalPhotos: Int) -> Double {
        if let target = targetKeepCount, totalPhotos > 0 {
            return min(max(Double(target) / Double(totalPhotos), 0.02), 0.5)
        }
        return keepRate
    }
}

// MARK: - Agent actions & explanations (Phase D)

enum AgentActionKind: String, Codable {
    case autoKeep, autoReject, autoHero, userKeep, userReject, userHero, tasteApply, stackResolve
}

struct AgentAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var photoID: UUID
    var clusterID: String?
    var kind: AgentActionKind
    var whyAction: String
    var timestamp: Date = Date()
}

struct SessionSummary: Equatable {
    var totalPhotos: Int
    var keepCount: Int
    var rejectCount: Int
    var uncertainResolved: Int
    var autoActions: Int
    var userOverrides: Int
    var feedbackEvents: Int

    var narrative: String {
        "Kept \(keepCount), rejected \(rejectCount), resolved \(uncertainResolved) close calls · \(autoActions) auto · \(userOverrides) overrides"
    }
}

// MARK: - Feedback (Phase B)

enum FeedbackKind: String, Codable {
    case keep, reject, hero, developAdjust
}

struct FeedbackEvent: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var photoID: UUID
    var kind: FeedbackKind
    var recipe: DevelopRecipe?
    var embedding: [Float]?
    var filename: String
    var timestamp: Date = Date()
    var weight: Double = 1.0
}

struct StackUndoSnapshot: Equatable {
    var clusterID: String
    var photoTiers: [UUID: PhotoTier]
    var timestamp: Date = Date()
}
