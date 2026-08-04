import Foundation
import CoreGraphics

typealias AssetID = UUID

enum AssetDecision: String, Codable, Hashable, CaseIterable, Identifiable {
    case undecided, cut, needsMe, keep, anchor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .undecided: "—"
        case .cut: "Cut"
        case .needsMe: "Needs me"
        case .keep: "Keep"
        case .anchor: "Anchor"
        }
    }

    var shortcut: String {
        switch self {
        case .undecided: ""
        case .cut: "X"
        case .needsMe: "M"
        case .keep: "K"
        case .anchor: "A"
        }
    }
}

enum WorkspaceLens: String, Hashable, CaseIterable, Identifiable {
    case attempts, light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attempts: "Attempts"
        case .light: "Light"
        }
    }

    var shortcut: String {
        switch self {
        case .attempts: "1"
        case .light: "2"
        }
    }
}

enum SourceReadiness: String, Hashable {
    case ready, findingMore, disconnected, missing, empty
}

/// Immutable photographic presentation unit. Geometry is predetermined; UX never stretches.
struct AssetPresentation: Identifiable, Hashable, Sendable {
    let id: AssetID
    let filename: String
    /// Width / height. Always > 0. Reserved before pixels arrive.
    let aspectRatio: CGFloat
    let previewPath: String?
    let thumbPath: String?
    let decision: AssetDecision
    let isProtected: Bool
    let caption: String?

    init(
        id: AssetID = AssetID(),
        filename: String,
        aspectRatio: CGFloat = 3.0 / 2.0,
        previewPath: String? = nil,
        thumbPath: String? = nil,
        decision: AssetDecision = .undecided,
        isProtected: Bool = false,
        caption: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.aspectRatio = max(aspectRatio, 0.05)
        self.previewPath = previewPath
        self.thumbPath = thumbPath
        self.decision = decision
        self.isProtected = isProtected
        self.caption = caption
    }
}

struct GroupPresentation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let assets: [AssetPresentation]
    let representativeID: AssetID?
    let relationshipNote: String?

    var representative: AssetPresentation? {
        if let representativeID {
            return assets.first { $0.id == representativeID } ?? assets.first
        }
        return assets.first
    }
}

struct ShootCardPresentation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let dateLabel: String?
    let locationLabel: String?
    let photographCount: Int
    let progressLabel: String?
    let previewAssets: [AssetPresentation]
    let readiness: SourceReadiness
    let boundaryWarning: String?
    let primaryActionTitle: String

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        dateLabel: String? = nil,
        locationLabel: String? = nil,
        photographCount: Int,
        progressLabel: String? = nil,
        previewAssets: [AssetPresentation] = [],
        readiness: SourceReadiness = .ready,
        boundaryWarning: String? = nil,
        primaryActionTitle: String = "Open"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.dateLabel = dateLabel
        self.locationLabel = locationLabel
        self.photographCount = photographCount
        self.progressLabel = progressLabel
        self.previewAssets = previewAssets
        self.readiness = readiness
        self.boundaryWarning = boundaryWarning
        self.primaryActionTitle = primaryActionTitle
    }
}

struct FinishedStripItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let photographCount: Int
    let thumbAssets: [AssetPresentation]
}

struct HomePresentation: Hashable, Sendable {
    let greeting: String
    let newSection: NewSection?
    let continueSection: ShootCardPresentation?
    let recentlyFinished: [FinishedStripItem]
    let readinessSummary: String?

    struct NewSection: Hashable, Sendable {
        let headline: String
        let detail: String
        let card: ShootCardPresentation
        let actionTitle: String
    }
}

struct WorkspacePresentation: Hashable, Sendable {
    let shootTitle: String
    let lens: WorkspaceLens
    let groups: [GroupPresentation]
    let selectedAssetID: AssetID?
    let selectedGroupID: String?
    let progressCurrent: Int
    let progressTotal: Int
    let inspectorAvailable: Bool

    var selectedGroup: GroupPresentation? {
        if let selectedGroupID {
            return groups.first { $0.id == selectedGroupID } ?? groups.first
        }
        return groups.first
    }

    var selectedAsset: AssetPresentation? {
        guard let selectedAssetID else { return selectedGroup?.representative }
        for group in groups {
            if let asset = group.assets.first(where: { $0.id == selectedAssetID }) {
                return asset
            }
        }
        return selectedGroup?.representative
    }

    var progressLabel: String {
        "\(progressCurrent) of \(progressTotal)"
    }

    /// Overlay selection / lens without rebuilding group payloads.
    func overlaying(
        lens: WorkspaceLens? = nil,
        selectedAssetID: AssetID? = nil,
        selectedGroupID: String? = nil
    ) -> WorkspacePresentation {
        WorkspacePresentation(
            shootTitle: shootTitle,
            lens: lens ?? self.lens,
            groups: groups,
            selectedAssetID: selectedAssetID ?? self.selectedAssetID,
            selectedGroupID: selectedGroupID ?? self.selectedGroupID,
            progressCurrent: progressCurrent,
            progressTotal: progressTotal,
            inspectorAvailable: inspectorAvailable
        )
    }
}

struct FinishPresentation: Hashable, Sendable {
    let shootTitle: String
    let assets: [AssetPresentation]
    let unresolvedCount: Int
    let protectedCount: Int
    let primaryActionTitle: String
    let secondaryReviewTitle: String

    var sequenceLabel: String {
        "\(assets.count) photographs"
    }
}

struct ShootSelectionPresentation: Hashable, Sendable {
    let readinessSummary: String
    let shoots: [ShootCardPresentation]
}
