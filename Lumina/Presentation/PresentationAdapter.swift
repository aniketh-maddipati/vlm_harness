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
            hasher.combine(photo.capturedAt)
            hasher.combine(photo.recipe)
        }
        hasher.combine(model.catalogQueue.folders.count)
        hasher.combine(model.catalogQueue.isIndexing)
        return "\(hasher.finalize())"
    }

    static func decision(for photo: PhotoRecord) -> AssetDecision {
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
            caption: photo.clusterLabel,
            qualityScore: photo.cullScore,
            capturedAt: photo.capturedAt
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
        var words = base
            .replacingOccurrences(of: "-", with: "_")
            .split(separator: "_")
            .map(String.init)

        let genericSuffixes: Set<String> = [
            "exposure", "raw", "jpg", "jpeg", "cr2", "nef", "arw", "dng",
            "shoot", "photos", "pics", "images", "export", "edit", "edited", "final",
        ]
        if words.count > 1, let last = words.last?.lowercased(), genericSuffixes.contains(last) {
            words.removeLast()
        }

        let titled = words.map { word -> String in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
        return titled.isEmpty ? "Untitled shoot" : titled.joined(separator: " ")
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
            return model.reviewClusters.enumerated().flatMap { index, cluster in
                let members = cluster.photoIDs.compactMap { byID[$0] }
                guard !members.isEmpty else { return [GroupPresentation]() }
                let repID = cluster.heroID ?? members.max(by: { $0.cullScore < $1.cullScore })?.id
                return timeBucketGroups(
                    from: members,
                    idPrefix: cluster.id,
                    titlePrefix: cluster.label.isEmpty ? "Subject \(index + 1)" : cluster.label,
                    category: .subject,
                    relationshipNote: cluster.whyGrouped,
                    representativeID: repID
                )
            }
        }

        return timeBucketGroups(
            from: photos,
            idPrefix: "subject",
            titlePrefix: "Subject",
            category: .subject,
            relationshipNote: nil,
            representativeID: nil
        )
    }

    /// Light lens reorganizes the same shoot into day + gap-based time rows.
    private static func lightGroups(from model: ProjectViewModel) -> [GroupPresentation] {
        guard let photos = model.project?.photos, !photos.isEmpty else { return [] }
        return timeBucketGroups(
            from: photos,
            idPrefix: "light",
            titlePrefix: "Roll",
            category: .time,
            relationshipNote: "Captured in the same session window",
            representativeID: nil
        )
    }

    /// Split large photo lists into manageable time rows — by day, then adaptive gaps.
    private static func timeBucketGroups(
        from photos: [PhotoRecord],
        idPrefix: String,
        titlePrefix: String,
        category: StackRowCategory,
        relationshipNote: String?,
        representativeID: AssetID?,
        maxPhotosPerBucket: Int = 28
    ) -> [GroupPresentation] {
        let buckets = adaptiveTimeBuckets(from: photos, maxPhotosPerBucket: maxPhotosPerBucket)
        guard !buckets.isEmpty else { return [] }

        return buckets.enumerated().map { index, slice in
            let assets = slice.map(asset(from:))
            let repPhoto = representativeID.flatMap { id in slice.first(where: { $0.id == id }) }
                ?? slice.max(by: { $0.cullScore < $1.cullScore })
            let repAssetID = repPhoto.flatMap { photo in assets.first(where: { $0.id == photo.id })?.id }
                ?? assets.first?.id
            let dates = slice.compactMap(\.capturedAt).sorted()
            let title = bucketTitle(
                prefix: titlePrefix,
                index: index + 1,
                totalBuckets: buckets.count,
                photos: slice
            )
            return GroupPresentation(
                id: "\(idPrefix)-\(index + 1)",
                title: title,
                subtitle: bucketSubtitle(for: slice),
                assets: assets,
                representativeID: repAssetID,
                relationshipNote: relationshipNote,
                rowCategory: category,
                timeStart: dates.first,
                timeEnd: dates.last
            )
        }
    }

    // MARK: - Adaptive time bucketing

    /// Groups photos by calendar day, then splits on natural capture gaps and size caps.
    private static func adaptiveTimeBuckets(
        from photos: [PhotoRecord],
        maxPhotosPerBucket: Int = 28
    ) -> [[PhotoRecord]] {
        let dated = photos.filter { $0.capturedAt != nil }.sorted {
            ($0.capturedAt ?? .distantPast) < ($1.capturedAt ?? .distantPast)
        }
        let undated = photos.filter { $0.capturedAt == nil }

        var buckets: [[PhotoRecord]] = []
        let calendar = Calendar.current
        let dayGroups = Dictionary(grouping: dated) { photo in
            calendar.startOfDay(for: photo.capturedAt!)
        }.sorted { $0.key < $1.key }

        for (_, dayPhotos) in dayGroups {
            buckets.append(contentsOf: gapBuckets(from: dayPhotos, maxSize: maxPhotosPerBucket))
        }
        if !undated.isEmpty {
            buckets.append(contentsOf: splitOversized(undated, maxSize: maxPhotosPerBucket))
        }
        return buckets
    }

    private static func gapBuckets(from sorted: [PhotoRecord], maxSize: Int) -> [[PhotoRecord]] {
        guard !sorted.isEmpty else { return [] }
        guard sorted.count > 1 else { return [sorted] }

        let splitThreshold = adaptiveGapThreshold(for: sorted)
        var buckets: [[PhotoRecord]] = []
        var current: [PhotoRecord] = [sorted[0]]

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let photo = sorted[i]
            let gap: TimeInterval
            if let a = prev.capturedAt, let b = photo.capturedAt {
                gap = b.timeIntervalSince(a)
            } else {
                gap = 0
            }
            let shouldSplit = gap > splitThreshold || current.count >= maxSize
            if shouldSplit {
                buckets.append(current)
                current = [photo]
            } else {
                current.append(photo)
            }
        }
        if !current.isEmpty { buckets.append(current) }
        return buckets.flatMap { splitOversized($0, maxSize: maxSize) }
    }

    private static func adaptiveGapThreshold(for sorted: [PhotoRecord]) -> TimeInterval {
        var gaps: [TimeInterval] = []
        for i in 1..<sorted.count {
            if let a = sorted[i - 1].capturedAt, let b = sorted[i].capturedAt {
                let gap = b.timeIntervalSince(a)
                if gap > 0 { gaps.append(gap) }
            }
        }
        guard !gaps.isEmpty else { return 12 * 60 }
        gaps.sort()
        let median = gaps[gaps.count / 2]
        // Pause longer than ~5× typical spacing, clamped between 3 and 45 minutes.
        return min(max(median * 5, 3 * 60), 45 * 60)
    }

    /// Hard-split buckets that still exceed the row cap at the largest internal gap.
    private static func splitOversized(_ photos: [PhotoRecord], maxSize: Int) -> [[PhotoRecord]] {
        guard photos.count > maxSize else { return photos.isEmpty ? [] : [photos] }
        var bestIndex = maxSize
        var bestGap: TimeInterval = -1
        for i in 1..<photos.count {
            let gap: TimeInterval
            if let a = photos[i - 1].capturedAt, let b = photos[i].capturedAt {
                gap = b.timeIntervalSince(a)
            } else {
                gap = 0
            }
            if gap > bestGap {
                bestGap = gap
                bestIndex = i
            }
        }
        let pivot = max(1, min(bestIndex, photos.count - 1))
        let left = Array(photos[..<pivot])
        let right = Array(photos[pivot...])
        return splitOversized(left, maxSize: maxSize) + splitOversized(right, maxSize: maxSize)
    }

    private static func bucketTitle(
        prefix: String,
        index: Int,
        totalBuckets: Int,
        photos: [PhotoRecord]
    ) -> String {
        let dates = photos.compactMap(\.capturedAt).sorted()
        guard let first = dates.first else {
            return "Unknown time · \(photos.count) photos"
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE MMM d"
        let dayLabel = dayFormatter.string(from: first)

        if dates.count <= 1 || dates.last == first {
            return "\(dayLabel) · \(shortTime(first))"
        }
        let range = "\(shortTime(first)) – \(shortTime(dates.last!))"
        if totalBuckets > 1, prefix != "Roll" {
            return "\(prefix) · \(dayLabel) · \(range)"
        }
        return "\(dayLabel) · \(range)"
    }

    private static func bucketSubtitle(for photos: [PhotoRecord]) -> String {
        let dated = photos.compactMap(\.capturedAt)
        let span: String
        if dated.count >= 2, let first = dated.min(), let last = dated.max(), last > first {
            let minutes = Int(last.timeIntervalSince(first) / 60)
            span = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m span" : "\(max(minutes, 1)) min span"
        } else if dated.count == 1 {
            span = "single moment"
        } else {
            span = "time unknown"
        }
        return "\(photos.count) photo\(photos.count == 1 ? "" : "s") · \(span)"
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
