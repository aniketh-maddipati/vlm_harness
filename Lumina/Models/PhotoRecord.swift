import Foundation

enum PhotoTier: String, Codable, CaseIterable {
    case keep
    case maybe
    case reject
    case unranked

    var label: String {
        switch self {
        case .keep: "Keep"
        case .maybe: "Maybe"
        case .reject: "Reject"
        case .unranked: "—"
        }
    }
}

struct PhotoRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var rawPath: String
    var filename: String
    var thumbPath: String?
    var capturedAt: Date?
    var burstID: String?
    var sharpness: Double
    var faceDetected: Bool
    var cullScore: Double
    var tier: PhotoTier
    var isFlagged: Bool
    var isBurstHero: Bool
    var perPhotoAdjustments: DevelopAdjustments?

    init(
        id: UUID = UUID(),
        rawPath: String,
        filename: String,
        thumbPath: String? = nil,
        capturedAt: Date? = nil,
        burstID: String? = nil,
        sharpness: Double = 0,
        faceDetected: Bool = false,
        cullScore: Double = 0,
        tier: PhotoTier = .unranked,
        isFlagged: Bool = false,
        isBurstHero: Bool = true,
        perPhotoAdjustments: DevelopAdjustments? = nil
    ) {
        self.id = id
        self.rawPath = rawPath
        self.filename = filename
        self.thumbPath = thumbPath
        self.capturedAt = capturedAt
        self.burstID = burstID
        self.sharpness = sharpness
        self.faceDetected = faceDetected
        self.cullScore = cullScore
        self.tier = tier
        self.isFlagged = isFlagged
        self.isBurstHero = isBurstHero
        self.perPhotoAdjustments = perPhotoAdjustments
    }

    var whySummary: String {
        var parts: [String] = []
        parts.append("Sharpness \(String(format: "%.2f", sharpness))")
        parts.append(faceDetected ? "Face detected" : "No face")
        if let burstID {
            parts.append(isBurstHero ? "Burst hero (\(burstID))" : "Burst alternate")
        }
        parts.append("Score \(String(format: "%.2f", cullScore))")
        return parts.joined(separator: " · ")
    }
}

struct DevelopAdjustments: Codable, Hashable {
    var exposure: Double = 0
    var temperature: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var vibrance: Double = 0

    static let zero = DevelopAdjustments()

    func merged(with global: DevelopAdjustments) -> DevelopAdjustments {
        DevelopAdjustments(
            exposure: global.exposure + exposure,
            temperature: global.temperature + temperature,
            contrast: global.contrast + contrast,
            highlights: global.highlights + highlights,
            shadows: global.shadows + shadows,
            vibrance: global.vibrance + vibrance
        )
    }
}

struct DevelopProfile: Codable {
    var exposure: Double = 0
    var temperature: Double = 6500
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var vibrance: Double = 0
    var sourceCount: Int = 0

    var asAdjustments: DevelopAdjustments {
        DevelopAdjustments(
            exposure: exposure,
            temperature: temperature,
            contrast: contrast,
            highlights: highlights,
            shadows: shadows,
            vibrance: vibrance
        )
    }
}

struct LuminaProject: Codable {
    var name: String
    var rawFolder: String?
    var jpgFolder: String?
    var keepRateTarget: Double = 0.10
    var profile: DevelopProfile = DevelopProfile()
    var globalAdjustments: DevelopAdjustments = .zero
    var photos: [PhotoRecord] = []
    var createdAt: Date = Date()
}

enum GridFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case keeps = "Keeps"
    case rejects = "Rejects"
    case flagged = "Needs you"

    var id: String { rawValue }
}
