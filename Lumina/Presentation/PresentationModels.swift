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
        case .needsMe: "Maybe"
        case .keep: "Keep"
        case .anchor: "Keep" // legacy — no longer surfaced in UI
        }
    }

    /// Workbench routing copy — where the photograph goes, not a quality judgment.
    var routingTitle: String {
        switch self {
        case .undecided: "—"
        case .cut: "Set aside"
        case .needsMe: "Hold"
        case .keep: "Add to set"
        case .anchor: "Add to set"
        }
    }

    /// Quiet marker on photographs that remain visible after a decision.
    var quietMarker: String {
        switch self {
        case .undecided: ""
        case .cut: "Set aside"
        case .needsMe: "Hold"
        case .keep, .anchor: "In set"
        }
    }

    var shortcut: String {
        switch self {
        case .undecided: ""
        case .cut: "X"
        case .needsMe: "M"
        case .keep: "S"
        case .anchor: "A"
        }
    }
}

/// How rows are grouped on the stack table.
enum StackRowCategory: String, Hashable, Sendable {
    case subject, time

    var label: String {
        switch self {
        case .subject: "Subject"
        case .time: "Time"
        }
    }
}

enum WorkspaceLens: String, Hashable, CaseIterable, Identifiable {
    case attempts, light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attempts: "Subject"
        case .light: "Time"
        }
    }

    var rowCategory: StackRowCategory {
        switch self {
        case .attempts: .subject
        case .light: .time
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
    /// Composite cull score for ranking alternatives within a set.
    let qualityScore: Double
    /// EXIF capture time when known.
    let capturedAt: Date?

    init(
        id: AssetID = AssetID(),
        filename: String,
        aspectRatio: CGFloat = 3.0 / 2.0,
        previewPath: String? = nil,
        thumbPath: String? = nil,
        decision: AssetDecision = .undecided,
        isProtected: Bool = false,
        caption: String? = nil,
        qualityScore: Double = 0,
        capturedAt: Date? = nil
    ) {
        self.id = id
        self.filename = filename
        self.aspectRatio = max(aspectRatio, 0.05)
        self.previewPath = previewPath
        self.thumbPath = thumbPath
        self.decision = decision
        self.isProtected = isProtected
        self.caption = caption
        self.qualityScore = qualityScore
        self.capturedAt = capturedAt
    }
}

struct GroupPresentation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let assets: [AssetPresentation]
    let representativeID: AssetID?
    let relationshipNote: String?
    let rowCategory: StackRowCategory
    let timeStart: Date?
    let timeEnd: Date?
    /// When one cluster splits into adjacent time buckets, shares this id.
    let siblingGroupID: String?
    let siblingPartIndex: Int?
    let siblingPartCount: Int?

    var representative: AssetPresentation? {
        if let representativeID {
            return assets.first { $0.id == representativeID } ?? assets.first
        }
        return assets.first
    }

    /// Best-quality frame — lead card on the right of the stack.
    var leadAsset: AssetPresentation? {
        if let rep = representative { return rep }
        return assets.max(by: { $0.qualityScore < $1.qualityScore }) ?? assets.first
    }

    /// Stable capture-time order for comparison rows.
    var captureOrderedAssets: [AssetPresentation] {
        assets.sorted {
            ($0.capturedAt ?? .distantPast) < ($1.capturedAt ?? .distantPast)
        }
    }

    /// Legacy alias — capture order, not quality-ranked stacks.
    func stackOrdered(leadID: AssetID?) -> [AssetPresentation] {
        captureOrderedAssets
    }

    var undecidedCount: Int {
        assets.filter { $0.decision == .undecided }.count
    }

    var keepCount: Int {
        assets.filter { $0.decision == .keep }.count
    }

    var foldCount: Int {
        assets.filter { $0.decision == .cut }.count
    }

    var isSiblingContinuation: Bool {
        siblingPartIndex.map { $0 > 1 } ?? false
    }

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        assets: [AssetPresentation],
        representativeID: AssetID? = nil,
        relationshipNote: String? = nil,
        rowCategory: StackRowCategory = .subject,
        timeStart: Date? = nil,
        timeEnd: Date? = nil,
        siblingGroupID: String? = nil,
        siblingPartIndex: Int? = nil,
        siblingPartCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.assets = assets
        self.representativeID = representativeID
        self.relationshipNote = relationshipNote
        self.rowCategory = rowCategory
        self.timeStart = timeStart
        self.timeEnd = timeEnd
        self.siblingGroupID = siblingGroupID
        self.siblingPartIndex = siblingPartIndex
        self.siblingPartCount = siblingPartCount
    }
}

/// Spatial display within the continuous photographic workspace.
/// Proof is no longer a destination — Read is a mode inside Story (⌘R).
enum WorkspaceStage: String, CaseIterable, Hashable, Sendable {
    case workbench, canvas, proof

    /// Stages shown in the header switch — Sources is routed separately.
    static var switcherCases: [WorkspaceStage] { [.workbench, .canvas] }

    var title: String {
        switch self {
        case .workbench: "Workbench"
        case .canvas: "Story"
        case .proof: "Read"
        }
    }
}

/// Which develop baseline the contextual strip previews.
enum TreatmentPreviewMode: String, Hashable, Sendable {
    case original, auto, current
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

/// Prompt to batch-apply a cull decision to lower-quality peers in the same subject set.
struct PeerCullSuggestion: Hashable, Sendable {
    let anchorAssetID: AssetID
    let peerAssets: [AssetPresentation]
    let suggestedDecision: AssetDecision
    let reason: String

    var peerCount: Int { peerAssets.count }
}
