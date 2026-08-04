import Foundation
import CoreGraphics

/// Thin adapter: existing project / catalog data → immutable presentation snapshots.
/// Call only when project state fingerprints change — never from every SwiftUI body tick.
@MainActor
enum PresentationAdapter {

    /// Cheap fingerprint of the project payload the UX snapshots depend on.
    static func projectFingerprint(_ model: ProjectViewModel) -> String {
        guard let project = model.project else {
            return "nil|\(model.canResumeLastProject)|\(model.catalogQueue.folders.count)|\(model.catalogQueue.isIndexing)"
        }
        var hasher = Hasher()
        hasher.combine(project.name)
        hasher.combine(project.rawFolder)
        hasher.combine(project.photos.count)
        hasher.combine(project.cursorPhotoID)
        // Decision / path churn that should refresh presentation.
        for photo in project.photos {
            hasher.combine(photo.id)
            hasher.combine(photo.tier)
            hasher.combine(photo.isFlagged)
            hasher.combine(photo.isBurstHero)
            hasher.combine(photo.gridThumbPath)
            hasher.combine(photo.thumbPath)
            hasher.combine(photo.proxyPath)
            hasher.combine(photo.clusterID)
            hasher.combine(photo.burstID)
        }
        hasher.combine(model.catalogQueue.folders.count)
        hasher.combine(model.catalogQueue.isIndexing)
        return "\(hasher.finalize())"
    }

    static func decision(for photo: PhotoRecord) -> AssetDecision {
        if photo.isBurstHero || photo.isClusterHero, photo.tier == .keep {
            return .anchor
        }
        if photo.isFlagged || photo.isUncertain {
            return .needsMe
        }
        switch photo.tier {
        case .keep: return .keep
        case .reject: return .cut
        case .unranked: return .undecided
        }
    }

    static func asset(from photo: PhotoRecord) -> AssetPresentation {
        AssetPresentation(
            id: photo.id,
            filename: photo.filename,
            aspectRatio: inferredAspect(for: photo),
            previewPath: photo.sharpPath ?? photo.previewPath,
            thumbPath: photo.displayThumbPath,
            decision: decision(for: photo),
            isProtected: photo.isBurstHero || photo.isClusterHero,
            caption: photo.clusterLabel
        )
    }

    /// Prefer stable geometry. Without stored dimensions keep a calm default —
    /// never invent a stretch that later jumps when a real preview arrives.
    private static func inferredAspect(for photo: PhotoRecord) -> CGFloat {
        _ = photo.previewLongEdge
        return 3.0 / 2.0
    }

    static func home(from model: ProjectViewModel) -> HomePresentation {
        let greeting = PresentationFixtures.homeResumed().greeting

        if model.project == nil {
            if model.canResumeLastProject {
                return HomePresentation(
                    greeting: greeting,
                    newSection: nil,
                    continueSection: ShootCardPresentation(
                        id: "resume-last",
                        title: "Continue where you left off",
                        photographCount: 0,
                        progressLabel: "Resume last shoot",
                        readiness: .ready,
                        primaryActionTitle: "Continue"
                    ),
                    recentlyFinished: [],
                    readinessSummary: readinessSummary(for: model) ?? "Open a shoot to begin"
                )
            }
            return HomePresentation(
                greeting: greeting,
                newSection: nil,
                continueSection: nil,
                recentlyFinished: [],
                readinessSummary: readinessSummary(for: model) ?? "Open a shoot to begin"
            )
        }

        guard let project = model.project else {
            return PresentationFixtures.homeEmpty()
        }

        let projectKey = project.rawFolder ?? project.name
        let previews = project.photos.prefix(5).map(asset(from:))
        let reviewed = project.photos.filter { $0.tier != .unranked || $0.userDecidedAt != nil }.count
        let attempts = max(model.reviewClusters.count, 1)
        let reviewedAttempts = model.reviewClusters.filter { cluster in
            let members = project.photos.filter { cluster.photoIDs.contains($0.id) }
            return members.allSatisfy { $0.tier != .unranked && !$0.isFlagged }
        }.count

        let continueCard = ShootCardPresentation(
            id: projectKey,
            title: project.name,
            dateLabel: dateLabel(for: project.photos),
            photographCount: project.photos.count,
            progressLabel: "\(reviewedAttempts) of \(attempts) attempts reviewed",
            previewAssets: Array(previews),
            readiness: .ready,
            primaryActionTitle: "Continue"
        )

        let unfinished = project.photos.filter { $0.tier == .unranked || $0.isFlagged }.count
        let newSection: HomePresentation.NewSection? = unfinished == project.photos.count && reviewed == 0
            ? .init(
                headline: "New",
                detail: "\(project.photos.count) photographs",
                card: ShootCardPresentation(
                    id: "new-\(projectKey)",
                    title: project.name,
                    dateLabel: dateLabel(for: project.photos),
                    photographCount: project.photos.count,
                    progressLabel: "\(project.photos.count) new photographs",
                    previewAssets: Array(previews),
                    readiness: .ready,
                    primaryActionTitle: "Review new photographs"
                ),
                actionTitle: "Review new photographs"
            )
            : nil

        return HomePresentation(
            greeting: greeting,
            newSection: newSection,
            continueSection: newSection == nil ? continueCard : nil,
            recentlyFinished: [],
            readinessSummary: readinessSummary(for: model)
        )
    }

    static func shootSelection(from model: ProjectViewModel) -> ShootSelectionPresentation {
        if model.catalogQueue.totalFolders > 0 {
            let shoots = model.catalogQueue.folders.prefix(24).map { folder -> ShootCardPresentation in
                ShootCardPresentation(
                    id: folder.id.uuidString,
                    title: folder.name,
                    photographCount: folder.photoCount,
                    previewAssets: [],
                    readiness: folder.status == .indexed || folder.status == .active ? .ready : .findingMore,
                    primaryActionTitle: "Open"
                )
            }
            return ShootSelectionPresentation(
                readinessSummary: readinessSummary(for: model) ?? "Scanning shoots",
                shoots: Array(shoots)
            )
        }

        if let project = model.project {
            return ShootSelectionPresentation(
                readinessSummary: "1 shoot ready",
                shoots: [
                    ShootCardPresentation(
                        id: project.rawFolder ?? project.name,
                        title: project.name,
                        dateLabel: dateLabel(for: project.photos),
                        photographCount: project.photos.count,
                        previewAssets: project.photos.prefix(5).map(asset(from:)),
                        readiness: .ready
                    )
                ]
            )
        }

        return ShootSelectionPresentation(readinessSummary: "Open a shoot to begin", shoots: [])
    }

    static func workspace(
        from model: ProjectViewModel,
        lens: WorkspaceLens,
        selectedAssetID: AssetID?
    ) -> WorkspacePresentation {
        guard let project = model.project else {
            return WorkspacePresentation(
                shootTitle: "Lumina",
                lens: lens,
                groups: [],
                selectedAssetID: nil,
                selectedGroupID: nil,
                progressCurrent: 0,
                progressTotal: 0,
                inspectorAvailable: false
            )
        }

        let groups: [GroupPresentation]
        switch lens {
        case .attempts:
            groups = attemptGroups(from: model)
        case .light:
            groups = lightGroups(from: model)
        }

        let cursor = selectedAssetID ?? model.cursor ?? groups.first?.representativeID
        let groupID: String? = {
            guard let cursor else { return groups.first?.id }
            return groups.first(where: { $0.assets.contains(where: { $0.id == cursor }) })?.id
                ?? groups.first?.id
        }()

        let decided = project.photos.filter { $0.tier != .unranked || $0.isFlagged }.count

        return WorkspacePresentation(
            shootTitle: project.name,
            lens: lens,
            groups: groups,
            selectedAssetID: cursor,
            selectedGroupID: groupID,
            progressCurrent: min(max(decided, 1), max(project.photos.count, 1)),
            progressTotal: max(project.photos.count, 1),
            inspectorAvailable: true
        )
    }

    static func finish(from model: ProjectViewModel) -> FinishPresentation {
        guard let project = model.project else {
            return FinishPresentation(
                shootTitle: "Lumina",
                assets: [],
                unresolvedCount: 0,
                protectedCount: 0,
                primaryActionTitle: "Finish",
                secondaryReviewTitle: "Review"
            )
        }
        let kept = project.photos.filter { $0.tier == .keep }.map(asset(from:))
        let unresolved = project.photos.filter { $0.tier == .unranked || $0.isFlagged }.count
        let protected = project.photos.filter { ($0.isBurstHero || $0.isClusterHero) && $0.tier == .keep }.count
        return FinishPresentation(
            shootTitle: project.name,
            assets: kept,
            unresolvedCount: unresolved,
            protectedCount: protected,
            primaryActionTitle: kept.isEmpty ? "Review keeps" : "Finish",
            secondaryReviewTitle: unresolved > 0 ? "Review unresolved" : "Review"
        )
    }

    private static func attemptGroups(from model: ProjectViewModel) -> [GroupPresentation] {
        guard let photos = model.project?.photos else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })

        if model.reviewClusters.isEmpty {
            return [
                GroupPresentation(
                    id: "all",
                    title: "Attempts",
                    subtitle: nil,
                    assets: photos.map(asset(from:)),
                    representativeID: model.cursor ?? photos.first?.id,
                    relationshipNote: nil
                )
            ]
        }

        return model.reviewClusters.enumerated().map { index, cluster in
            let members = cluster.photoIDs.compactMap { byID[$0] }.map(asset(from:))
            let note: String? = {
                let dates = cluster.photoIDs.compactMap { byID[$0]?.capturedAt }.sorted()
                guard let first = dates.first, let last = dates.last, dates.count > 1 else { return nil }
                let seconds = Int(last.timeIntervalSince(first))
                if seconds < 60 { return "\(seconds) seconds" }
                return "\(seconds / 60) min"
            }()
            return GroupPresentation(
                id: cluster.id,
                title: String(format: "A%02d", index + 1),
                subtitle: cluster.whyGrouped.isEmpty ? cluster.label : cluster.whyGrouped,
                assets: members,
                representativeID: cluster.heroID ?? members.first?.id,
                relationshipNote: note
            )
        }
    }

    /// Light palettes reuse cluster ordering as a provisional stand-in until Phase 2
    /// supplies tonal grouping. No color analysis happens here.
    private static func lightGroups(from model: ProjectViewModel) -> [GroupPresentation] {
        attemptGroups(from: model).enumerated().map { index, group in
            GroupPresentation(
                id: "light-\(group.id)",
                title: group.title.replacingOccurrences(of: "A", with: "P"),
                subtitle: "Related treatment family",
                assets: group.assets,
                representativeID: group.representativeID,
                relationshipNote: index == 0 ? "Switching lens reorganizes — files stay put" : nil
            )
        }
    }

    private static func readinessSummary(for model: ProjectViewModel) -> String? {
        let total = model.catalogQueue.totalFolders
        guard total > 0 else { return nil }
        let ready = model.catalogQueue.folders.filter {
            $0.status == .indexed || $0.status == .active || $0.status == .cleared
        }.count
        if model.catalogQueue.isIndexing || model.catalogQueue.isScanning {
            return "\(ready) shoots ready · finding more"
        }
        return "\(ready) of \(total) shoots ready"
    }

    private static func dateLabel(for photos: [PhotoRecord]) -> String? {
        guard let date = photos.compactMap(\.capturedAt).min() else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter.string(from: date)
    }
}
