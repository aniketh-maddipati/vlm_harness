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

    /// Prefer oriented JPEG dimensions; fall back to a calm default without stretch-on-load.
    private static func inferredAspect(for photo: PhotoRecord) -> CGFloat {
        let candidates = [photo.sharpPath, photo.previewPath, photo.thumbPath, photo.gridThumbPath]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        for path in candidates {
            if let size = ImagePixelFormat.orientedPixelSize(at: URL(fileURLWithPath: path)) {
                return AspectFitGeometry.orientedAspectRatio(width: size.width, height: size.height)
            }
        }
        if photo.previewLongEdge > 0 {
            return 3.0 / 2.0
        }
        return 3.0 / 2.0
    }

    static func readableShootTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmed as NSString).lastPathComponent
        let spaced = base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        return spaced.isEmpty ? "Untitled shoot" : spaced
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
            shootTitle: readableShootTitle(project.name),
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
        guard let photos = model.project?.photos, !photos.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })

        if !model.reviewClusters.isEmpty {
            return model.reviewClusters.enumerated().compactMap { index, cluster in
                let members = cluster.photoIDs.compactMap { byID[$0] }
                guard !members.isEmpty else { return nil }
                return neutralGroup(
                    id: cluster.id,
                    index: index + 1,
                    assets: members.map(asset(from:)),
                    representativeID: cluster.heroID ?? members.first?.id,
                    sourcePhotos: members
                )
            }
        }

        return editorialChunks(from: photos, prefix: "Group", idPrefix: "attempt")
    }

    /// Light lens reorganizes the same shoot into illumination-time rows — no composition claims.
    private static func lightGroups(from model: ProjectViewModel) -> [GroupPresentation] {
        guard let photos = model.project?.photos, !photos.isEmpty else { return [] }
        let sorted = photos.sorted {
            ($0.capturedAt ?? .distantPast) < ($1.capturedAt ?? .distantPast)
        }
        return illuminationChunks(from: sorted)
    }

    private static func neutralGroup(
        id: String,
        index: Int,
        assets: [AssetPresentation],
        representativeID: AssetID?,
        sourcePhotos: [PhotoRecord]
    ) -> GroupPresentation {
        GroupPresentation(
            id: id,
            title: "Group \(index) · \(assets.count) photograph\(assets.count == 1 ? "" : "s")",
            subtitle: timeRangeLabel(for: sourcePhotos),
            assets: assets,
            representativeID: representativeID,
            relationshipNote: nil
        )
    }

    /// Editorial rows for shoots without trustworthy semantic clusters.
    private static func editorialChunks(
        from photos: [PhotoRecord],
        prefix: String,
        idPrefix: String,
        chunkSize: Int = 6
    ) -> [GroupPresentation] {
        let sorted = photos.sorted {
            ($0.capturedAt ?? .distantPast) < ($1.capturedAt ?? .distantPast)
        }
        guard !sorted.isEmpty else { return [] }
        var groups: [GroupPresentation] = []
        var index = 0
        var groupNumber = 1
        while index < sorted.count {
            let end = min(index + chunkSize, sorted.count)
            let slice = Array(sorted[index..<end])
            let assets = slice.map(asset(from:))
            groups.append(
                GroupPresentation(
                    id: "\(idPrefix)-\(groupNumber)",
                    title: "\(prefix) \(groupNumber) · \(assets.count) photograph\(assets.count == 1 ? "" : "s")",
                    subtitle: timeRangeLabel(for: slice),
                    assets: assets,
                    representativeID: assets.first?.id,
                    relationshipNote: nil
                )
            )
            index = end
            groupNumber += 1
        }
        return groups
    }

    /// Light lens: merge photographs captured within ~20 minutes into one row.
    private static func illuminationChunks(from photos: [PhotoRecord], windowSeconds: TimeInterval = 20 * 60) -> [GroupPresentation] {
        guard !photos.isEmpty else { return [] }
        var groups: [[PhotoRecord]] = []
        var current: [PhotoRecord] = []
        var windowStart: Date?

        for photo in photos {
            let stamp = photo.capturedAt
            if current.isEmpty {
                current = [photo]
                windowStart = stamp
                continue
            }
            if let start = windowStart, let stamp,
               stamp.timeIntervalSince(start) <= windowSeconds {
                current.append(photo)
            } else {
                groups.append(current)
                current = [photo]
                windowStart = stamp
            }
        }
        if !current.isEmpty { groups.append(current) }

        return groups.enumerated().map { index, slice in
            let assets = slice.map(asset(from:))
            return GroupPresentation(
                id: "light-\(index + 1)",
                title: "Light row \(index + 1) · \(assets.count) photograph\(assets.count == 1 ? "" : "s")",
                subtitle: timeRangeLabel(for: slice),
                assets: assets,
                representativeID: assets.first?.id,
                relationshipNote: nil
            )
        }
    }

    private static func timeRangeLabel(for photos: [PhotoRecord]) -> String? {
        let dates = photos.compactMap(\.capturedAt).sorted()
        guard let first = dates.first else { return nil }
        guard dates.count > 1, let last = dates.last, last > first else {
            return shortTime(first)
        }
        return "\(shortTime(first)) – \(shortTime(last))"
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
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
