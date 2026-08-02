import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ProjectViewModel {
    var project: LuminaProject?
    var selectedPhotoID: UUID?
    var sortMode: SortMode = .similar
    var filter: GridFilter = .all
    var statusMessage = "Import photos to begin."
    var isBusy = false
    var isImporting = false
    var importFinishing = false
    var importProgress = ImportProgress.zero
    var importPreviewPhotos: [PhotoRecord] = []
    var showBefore = false
    var compareMix: Double = 1
    var softRender = SoftRenderController()
    var activeClusterIndex: Int = 0
    var appSpine: AppSpine = .stackFeed
    var groupPhase: GroupPhase = .intro
    var manualPickIDs: Set<UUID> = []
    var jobBrief: JobBrief = JobBrief()
    var agentLog: [AgentAction] = []
    var agentPlanText = ""
    var sessionSummary: SessionSummary?
    var showSessionSummary = false
    var exportPayoff: ExportPayoffState?
    var showExportPayoff = false
    var canResumeLastProject = false
    private var undoSnapshots: [StackUndoSnapshot] = []

    enum AppSpine: String, Equatable {
        case stackFeed
        case reviewingSet
        case sessionComplete
        case browsingKeeps
    }

    /// Back-compat for keeps browser layout checks.
    var viewMode: ViewMode {
        appSpine == .browsingKeeps ? .overview : .session
    }

    enum ViewMode: String, CaseIterable {
        case session = "Session"
        case overview = "Overview"
    }

    enum GroupPhase: String, Hashable {
        case intro
        case pick
        case decide
        case done
    }

    enum KeepsBrowseLayout: Equatable {
        case carousel
        case focus
    }

    var keepsBrowseLayout: KeepsBrowseLayout = .carousel

    var selectedPhoto: PhotoRecord? {
        guard let id = selectedPhotoID else { return nil }
        return project?.photos.first { $0.id == id }
    }

    var displayedPhotos: [PhotoRecord] {
        guard let photos = project?.photos else { return [] }
        var list = CullEngine.sorted(photos, by: sortMode)
        switch filter {
        case .all: break
        case .keeps: list = list.filter { $0.tier == .keep }
        case .rejects: list = list.filter { $0.tier == .reject }
        case .flagged: list = list.filter(\.isUncertain)
        }
        return list
    }

    /// Sets worth reviewing: multi-photo first, then meaningful singles.
    var reviewClusters: [PhotoCluster] {
        let all = clusters
        let multi = all.filter { $0.photoIDs.count >= 2 }
        if !multi.isEmpty { return multi }
        return all
    }

    var clusters: [PhotoCluster] {
        guard let photos = project?.photos else { return [] }
        return CullEngine.clusters(from: photos)
    }

    var currentCluster: PhotoCluster? {
        let list = reviewClusters
        guard !list.isEmpty else { return nil }
        return list[min(activeClusterIndex, list.count - 1)]
    }

    var uncertainPhotos: [PhotoRecord] {
        project?.photos.filter(\.isUncertain) ?? []
    }

    var keepCount: Int { project?.photos.filter { $0.tier == .keep }.count ?? 0 }
    var totalCount: Int { project?.photos.count ?? 0 }
    var uncertainCount: Int { uncertainPhotos.count }

    var decisionBudgetText: String {
        "\(uncertainCount) need\(uncertainCount == 1 ? "s" : "") you"
    }

    var extractedProfile: DevelopRecipe {
        project?.profile ?? .neutral
    }

    var tasteSourceCount: Int {
        project?.tasteSourceCount ?? 0
    }

    var tasteStrength: Double {
        get { project?.tasteStrength ?? 1.0 }
        set {
            guard var project else { return }
            project.tasteStrength = min(max(newValue, 0), 1.5)
            self.project = project
            persistDebounced()
        }
    }

    var tasteSummaryText: String {
        TasteProfileDescription.summary(profile: extractedProfile, sourceCount: tasteSourceCount)
    }

    func appliedRecipe(for photo: PhotoRecord) -> DevelopRecipe {
        photo.effectiveRecipe.withTasteStrength(tasteStrength)
    }

    var sessionProgressText: String {
        let n = reviewClusters.count
        guard n > 0 else { return "No sets" }
        if groupPhase == .done { return "Complete" }
        return "Set \(activeClusterIndex + 1) of \(n)"
    }

    // MARK: - Import

    func importPhotos(sourceFolder: URL, photoURLs: [URL]?, jpgURL: URL?) async {
        isBusy = true
        isImporting = true
        importFinishing = false
        importProgress = ImportProgress.zero
        importPreviewPhotos = []
        defer {
            isBusy = false
        }

        let stream = ImportPipeline.importProject(
            sourceFolder: sourceFolder,
            photoURLs: photoURLs,
            jpgFolder: jpgURL,
            keepRate: jobBrief.resolvedKeepRate(totalPhotos: project?.photos.count ?? 1000)
        )

        for await event in stream {
            switch event {
            case .progress(let progress):
                withAnimation(.easeInOut(duration: 0.55)) {
                    importProgress = progress
                }
                statusMessage = progress.detail
            case .status(let msg):
                statusMessage = msg
            case .photosReady(let photos, let profile):
                let p = LuminaProject(
                    name: sourceFolder.lastPathComponent,
                    rawFolder: sourceFolder.path,
                    jpgFolder: jpgURL?.path,
                    profile: profile,
                    tasteSourceCount: 0,
                    photos: photos
                )
                withAnimation(.easeInOut(duration: 0.4)) {
                    project = p
                    importPreviewPhotos = photos
                }
                selectedPhotoID = photos.first?.id
            case .photosUpdated(let photos):
                withAnimation(.easeInOut(duration: 0.35)) {
                    project?.photos = photos
                    importPreviewPhotos = photos
                }
            case .finished(let finished):
                withAnimation(.easeInOut(duration: 0.5)) {
                    importFinishing = true
                    importProgress = ImportProgress(
                        phase: .ready,
                        detail: "Opening your sets…",
                        completed: finished.photos.count,
                        total: finished.photos.count,
                        overallFraction: 1,
                        recentThumbPaths: importProgress.recentThumbPaths
                    )
                }
                try? await Task.sleep(nanoseconds: 650_000_000)
                var finished = finished
                finished.collections = ExportService.draftCollections(from: finished.photos)
                project = finished
                importPreviewPhotos = finished.photos
                ProjectStore.saveLastProjectName(finished.name)
                withAnimation(.easeInOut(duration: 0.65)) {
                    sortMode = .similar
                    appSpine = .stackFeed
                    activeClusterIndex = 0
                    groupPhase = .intro
                    manualPickIDs = []
                }
                if let hero = CullEngine.clusters(from: finished.photos).first?.heroID {
                    selectedPhotoID = hero
                } else {
                    selectedPhotoID = finished.photos.first?.id
                }
                let sets = reviewClusters.count
                statusMessage = "Meet your sets · \(sets) groups"
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.easeInOut(duration: 0.55)) {
                    isImporting = false
                    importFinishing = false
                }
            case .failed(let msg):
                statusMessage = msg
                withAnimation(.easeInOut(duration: 0.35)) {
                    isImporting = false
                    importFinishing = false
                }
            }
        }
    }

    func pickRAWFolder() {
        guard let raw = pickFolder(message: "Select the folder of RAW photos from this shoot") else { return }
        let jpgPanel = NSOpenPanel()
        jpgPanel.canChooseDirectories = true
        jpgPanel.canChooseFiles = false
        jpgPanel.allowsMultipleSelection = false
        jpgPanel.message = "Select a folder of past edited JPGs to learn your look (Cancel to skip)"
        jpgPanel.prompt = "Use for taste"
        let jpgURL = jpgPanel.runModal() == .OK ? jpgPanel.url : nil
        Task {
            await importPhotos(sourceFolder: raw, photoURLs: nil, jpgURL: jpgURL)
        }
    }

    func pickImportSources() { pickRAWFolder() }

    func refreshResumeAvailability() {
        canResumeLastProject = (try? ProjectStore.loadLastProject()) != nil
    }

    func resumeLastProject() {
        guard let saved = try? ProjectStore.loadLastProject() else {
            statusMessage = "No saved project found."
            canResumeLastProject = false
            return
        }
        project = saved
        sortMode = .similar
        appSpine = .stackFeed
        activeClusterIndex = 0
        groupPhase = .intro
        selectedPhotoID = saved.photos.first?.id
        statusMessage = "Resumed \(saved.name) · \(keepCount) keeps"
    }

    func ingestFromDroppedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var scanRoot: URL?
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                scanRoot = url
                break
            } else if MediaFormats.isImportable(url) {
                scanRoot = url.deletingLastPathComponent()
                break
            }
        }
        guard let root = scanRoot else {
            statusMessage = "No importable photos in drop."
            return
        }
        Task {
            await importPhotos(sourceFolder: root, photoURLs: nil, jpgURL: nil)
        }
    }

    // MARK: - Stack feed navigation

    func openStack(at index: Int) {
        activeClusterIndex = index
        groupPhase = .intro
        manualPickIDs = []
        snapshotStackForUndo()
        withAnimation(.easeInOut(duration: 0.35)) {
            appSpine = .reviewingSet
        }
        let clusters = reviewClusters
        guard index >= 0, index < clusters.count else { return }
        if let hero = clusters[index].heroID {
            selectPhoto(hero)
        }
        statusMessage = clusters[index].whyGrouped
    }

    func backToStackFeed() {
        withAnimation(.easeInOut(duration: 0.35)) {
            appSpine = .stackFeed
            groupPhase = .intro
        }
        statusMessage = "\(uncertainCount) need\(uncertainCount == 1 ? "s" : "") you"
    }

    // MARK: - Selection

    func selectPhoto(_ id: UUID) {
        let start = CFAbsoluteTimeGetCurrent()
        selectedPhotoID = id
        if groupPhase == .decide || appSpine == .browsingKeeps {
            playSoftRender(for: id)
        } else {
            softRender.mix = 1
        }
        if let photo = project?.photos.first(where: { $0.id == id }) {
            prefetchPhotoDisplay(photo)
        }
        LatencyMetrics.record("navigation.select", milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    func advanceFrame() {
        switch appSpine {
        case .browsingKeeps:
            nextKeep()
        case .reviewingSet where groupPhase == .decide:
            nextUncertainInCluster()
        default:
            break
        }
    }

    func retreatFrame() {
        switch appSpine {
        case .browsingKeeps:
            previousKeep()
        case .reviewingSet where groupPhase == .decide:
            previousUncertain()
        default:
            break
        }
    }

    func toggleKeep() {
        guard selectedPhotoID != nil else { return }
        markKeep()
    }

    func toggleReject() {
        guard selectedPhotoID != nil else { return }
        markReject()
    }

    func prefetchStackFeed(around index: Int) {
        let clusters = reviewClusters
        guard !clusters.isEmpty, let photos = project?.photos else { return }
        let map = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        var paths: [String] = []
        let lo = max(0, index - 2)
        let hi = min(clusters.count - 1, index + 4)
        for i in lo...hi {
            for id in clusters[i].photoIDs.prefix(4) {
                guard let photo = map[id] else { continue }
                paths.append(contentsOf: [
                    photo.previewPath,
                    photo.gridThumbPath,
                    photo.thumbPath,
                    photo.sharpPath,
                ].compactMap { $0 })
            }
        }
        Task {
            await PhotoImageCache.shared.prefetch(Array(Set(paths)))
        }
    }

    func prefetchPhotoDisplay(_ photo: PhotoRecord) {
        var paths = [photo.previewPath, photo.sharpPath, photo.proxyPath].compactMap { $0 }

        if appSpine == .browsingKeeps {
            let list = displayedPhotos
            if let idx = list.firstIndex(where: { $0.id == photo.id }) {
                let lo = max(0, idx - 5)
                let hi = min(list.count - 1, idx + 5)
                for neighbor in list[lo...hi] {
                    paths.append(contentsOf: [
                        neighbor.previewPath,
                        neighbor.sharpPath,
                        neighbor.proxyPath,
                    ].compactMap { $0 })
                }
            }
        }

        if let cluster = currentCluster, let photos = project?.photos {
            let map = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
            let neighbors = cluster.photoIDs.compactMap { map[$0] }
            if let idx = neighbors.firstIndex(where: { $0.id == photo.id }) {
                let lo = max(0, idx - 2)
                let hi = min(neighbors.count - 1, idx + 2)
                for n in neighbors[lo...hi] {
                    paths.append(contentsOf: [n.previewPath, n.sharpPath].compactMap { $0 })
                }
            }
        }
        Task {
            await PhotoImageCache.shared.prefetch(Array(Set(paths)))
        }
    }

    // MARK: - Keeps browser

    func prepareKeepsBrowser() {
        filter = .keeps
        if selectedPhotoID == nil || !displayedPhotos.contains(where: { $0.id == selectedPhotoID }) {
            selectedPhotoID = displayedPhotos.first?.id
        }
        if let id = selectedPhotoID {
            selectPhoto(id)
        }
    }

    func enterKeepsBrowser() {
        keepsBrowseLayout = .carousel
        appSpine = .browsingKeeps
        prepareKeepsBrowser()
        statusMessage = "\(keepCount) keeps · browse and enlarge"
    }

    func focusKeep() {
        guard selectedPhoto != nil else { return }
        withAnimation(.spring(duration: 0.52, bounce: 0.12)) {
            keepsBrowseLayout = .focus
        }
        if let photo = selectedPhoto {
            prefetchPhotoDisplay(photo)
            playSoftRender(for: photo.id)
        }
        statusMessage = "Loupe · Esc for carousel"
    }

    func unfocusKeep() {
        withAnimation(.spring(duration: 0.48, bounce: 0.1)) {
            keepsBrowseLayout = .carousel
        }
        statusMessage = "\(keepCount) keeps"
    }

    func nextKeep() {
        navigateKeep(by: 1)
    }

    func previousKeep() {
        navigateKeep(by: -1)
    }

    private func navigateKeep(by delta: Int) {
        let list = displayedPhotos
        guard !list.isEmpty else { return }
        guard let current = selectedPhotoID,
              let index = list.firstIndex(where: { $0.id == current }) else {
            selectPhoto(list[0].id)
            return
        }
        let next = list[max(0, min(list.count - 1, index + delta))]
        selectPhoto(next.id)
    }

    func playSoftRender(for id: UUID) {
        guard let photo = project?.photos.first(where: { $0.id == id }),
              photo.recipe != nil else {
            softRender.mix = 1
            return
        }
        softRender.play()
    }

    // MARK: - Tiers

    func setTier(_ tier: PhotoTier, for photoID: UUID, userInitiated: Bool = true) {
        guard var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == photoID }) else { return }
        let photo = project.photos[index]
        project.photos[index].tier = tier
        project.photos[index].isFlagged = false
        project.photos[index].uncertaintyKind = .none
        project.photos[index].whyUncertain = nil
        project.photos[index].cullConfidence = 1
        if userInitiated {
            let kind: AgentActionKind = tier == .keep ? .userKeep : .userReject
            let why = tier == .keep ? "You kept this photo" : "You rejected this photo"
            project.photos[index].whyAction = why
            agentLog.append(AgentAction(
                photoID: photoID,
                clusterID: photo.clusterID,
                kind: kind,
                whyAction: why
            ))
            let feedback: FeedbackKind = tier == .keep ? .keep : .reject
            TasteLearning.learnFromUserDecision(photo: project.photos[index], kind: feedback, projectName: project.name)
            reapplyTasteAndUncertainty()
        }
        self.project = project
        persistDebounced()
    }

    func toggleFlag() {
        guard var project, let id = selectedPhotoID,
              let index = project.photos.firstIndex(where: { $0.id == id }) else { return }
        project.photos[index].isFlagged.toggle()
        if project.photos[index].isFlagged {
            project.photos[index].uncertaintyKind = .cullBorderline
            project.photos[index].whyUncertain = "Flagged for another look"
        } else {
            project.photos[index].uncertaintyKind = .none
            project.photos[index].whyUncertain = nil
            CullEngine.assignConfidence(&project.photos)
        }
        self.project = project
        persistDebounced()
    }

    func markKeep() {
        guard let id = selectedPhotoID else { return }
        setTier(.keep, for: id)
        advanceAfterDecision()
    }

    func markReject() {
        guard let id = selectedPhotoID else { return }
        setTier(.reject, for: id)
        advanceAfterDecision()
    }

    func markHero() {
        guard let id = selectedPhotoID, var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == id }) else { return }
        let photo = project.photos[index]
        project.photos[index].isBurstHero = true
        project.photos[index].isClusterHero = true
        project.photos[index].tier = .keep
        project.photos[index].isFlagged = false
        project.photos[index].uncertaintyKind = .none
        project.photos[index].whyAction = "Marked as hero"
        agentLog.append(AgentAction(
            photoID: id,
            clusterID: photo.clusterID,
            kind: .userHero,
            whyAction: "You marked hero"
        ))
        TasteLearning.learnFromUserDecision(photo: project.photos[index], kind: .hero, projectName: project.name)
        self.project = project
        persistDebounced()
        reapplyTasteAndUncertainty()
        advanceAfterDecision()
    }

    private func advanceAfterDecision() {
        guard groupPhase == .decide, let cluster = currentCluster else {
            statusMessage = "\(keepCount)/\(totalCount) kept"
            return
        }
        let left = uncertainInCluster(cluster).filter { $0.id != selectedPhotoID }
        if let next = left.first {
            selectPhoto(next.id)
            statusMessage = "\(left.count) close calls left in this set"
        } else {
            statusMessage = "Set clear · next when ready"
        }
    }

    func advanceUncertain() { advanceAfterDecision() }

    func previousUncertain() {
        guard let cluster = currentCluster else { return }
        let list = uncertainInCluster(cluster)
        guard let current = selectedPhotoID,
              let index = list.firstIndex(where: { $0.id == current }) else { return }
        selectPhoto(list[max(index - 1, 0)].id)
    }

    func nextUncertainInCluster() {
        guard let cluster = currentCluster else { return }
        let list = uncertainInCluster(cluster)
        guard let current = selectedPhotoID,
              let index = list.firstIndex(where: { $0.id == current }) else { return }
        selectPhoto(list[min(index + 1, list.count - 1)].id)
    }

    func advanceCluster() {
        let all = reviewClusters
        guard !all.isEmpty else {
            completeSession()
            return
        }
        if activeClusterIndex >= all.count - 1 {
            completeSession()
            return
        }
        activeClusterIndex += 1
        appSpine = .reviewingSet
        groupPhase = .intro
        manualPickIDs = []
        if let hero = all[activeClusterIndex].heroID {
            selectPhoto(hero)
        }
        statusMessage = "Set \(activeClusterIndex + 1)/\(all.count) · \(all[activeClusterIndex].whyGrouped)"
    }

    func previousCluster() {
        let all = reviewClusters
        guard !all.isEmpty else { return }
        activeClusterIndex = max(activeClusterIndex - 1, 0)
        appSpine = .reviewingSet
        groupPhase = .intro
        manualPickIDs = []
        if let hero = all[activeClusterIndex].heroID {
            selectPhoto(hero)
        }
    }

    // MARK: - Group pick flow

    func seedPickFromHero(cluster: PhotoCluster) {
        manualPickIDs = Set(cluster.heroID.map { [$0] } ?? [])
        if let photos = project?.photos {
            for p in photos where p.clusterID == cluster.id && p.tier == .keep {
                manualPickIDs.insert(p.id)
            }
        }
    }

    func toggleManualPick(_ id: UUID) {
        if manualPickIDs.contains(id) { manualPickIDs.remove(id) }
        else { manualPickIDs.insert(id) }
    }

    func applyManualPicks(in cluster: PhotoCluster) {
        snapshotStackForUndo()
        guard var project else { return }
        for index in project.photos.indices where project.photos[index].clusterID == cluster.id {
            let id = project.photos[index].id
            if manualPickIDs.contains(id) {
                project.photos[index].tier = .keep
                project.photos[index].isClusterHero = (id == cluster.heroID) || manualPickIDs.count == 1
                project.photos[index].isFlagged = false
                project.photos[index].uncertaintyKind = .none
                project.photos[index].whyUncertain = nil
            } else {
                project.photos[index].tier = .reject
                project.photos[index].isFlagged = false
                project.photos[index].uncertaintyKind = .none
                project.photos[index].whyUncertain = nil
            }
        }
        self.project = project
        persistDebounced()
        agentLog.append(AgentAction(
            photoID: cluster.heroID ?? cluster.photoIDs[0],
            clusterID: cluster.id,
            kind: .stackResolve,
            whyAction: "Resolved stack · \(manualPickIDs.count) keeps"
        ))
    }

    func confirmPicksAndAdvance(cluster: PhotoCluster) {
        applyManualPicks(in: cluster)
        let left = uncertainInCluster(cluster)
        withAnimation(.easeInOut(duration: 0.32)) {
            if left.isEmpty {
                advanceCluster()
            } else {
                groupPhase = .decide
                if let first = left.first { selectPhoto(first.id) }
                statusMessage = "\(left.count) close calls in this set"
            }
        }
    }

    func skipPicksUseModel(cluster: PhotoCluster) {
        // Keep model tiers; only surface uncertain for decide
        withAnimation(.easeInOut(duration: 0.32)) {
            let left = uncertainInCluster(cluster)
            if left.isEmpty {
                advanceCluster()
            } else {
                groupPhase = .decide
                if let first = left.first { selectPhoto(first.id) }
                statusMessage = "Model picks · \(left.count) need you"
            }
        }
    }

    func completeSession() {
        guard let project else { return }
        let feedbackCount = (try? FeedbackStore.load(project: project.name).count) ?? 0
        sessionSummary = PhotoAgentOrchestrator.buildSessionSummary(
            photos: project.photos,
            agentLog: agentLog,
            feedbackCount: feedbackCount
        )
        withAnimation {
            groupPhase = .done
            appSpine = .sessionComplete
            showSessionSummary = true
        }
        statusMessage = sessionSummary?.narrative ?? "Session clear · \(keepCount) keeps"
    }

    func undoLastStack() {
        guard var project, let snapshot = undoSnapshots.popLast() else { return }
        for index in project.photos.indices {
            let id = project.photos[index].id
            if let tier = snapshot.photoTiers[id] {
                project.photos[index].tier = tier
            }
        }
        CullEngine.assignConfidence(&project.photos)
        self.project = project
        persistDebounced()
        statusMessage = "Undid changes to set"
    }

    private func snapshotStackForUndo() {
        guard let cluster = currentCluster, var photos = project?.photos else { return }
        var tiers: [UUID: PhotoTier] = [:]
        for id in cluster.photoIDs {
            if let p = photos.first(where: { $0.id == id }) {
                tiers[id] = p.tier
            }
        }
        undoSnapshots.append(StackUndoSnapshot(clusterID: cluster.id, photoTiers: tiers))
        if undoSnapshots.count > 20 { undoSnapshots.removeFirst() }
    }

    private func reapplyTasteAndUncertainty() {
        guard var project else { return }
        let library = (try? TasteIndex.load(project: project.name)) ?? []
        TasteRetriever.applyRecipes(to: &project.photos, library: library, baseline: project.profile)
        CullEngine.assignConfidence(&project.photos)
        self.project = project
    }

    func exportCarousel() {
        guard let project else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose export destination folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isBusy = true
        statusMessage = "Exporting carousel…"
        let snapshot = project
        let strength = tasteStrength

        Task {
            do {
                let outcome = try await ExportService.exportCollections(
                    project: snapshot,
                    tasteStrength: strength,
                    aspects: [.fourByFive],
                    writeXMP: true,
                    to: folder
                ) { [weak self] msg in
                    Task { @MainActor in self?.statusMessage = msg }
                }
                await MainActor.run {
                    self.isBusy = false
                    self.statusMessage = "Exported to \(outcome.root.path)"
                    let reveal = outcome.carouselFolder ?? outcome.root
                    NSWorkspace.shared.activateFileViewerSelecting([reveal])
                    self.exportPayoff = ExportPayoffState(
                        exportRoot: outcome.root,
                        carouselFolder: outcome.carouselFolder,
                        imageURLs: outcome.carouselImageURLs,
                        tasteSummary: self.tasteSummaryText,
                        keepCount: self.keepCount
                    )
                    self.showExportPayoff = true
                    self.persistDebounced()
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Helpers

    private func pickFolder(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func persistDebounced() {
        guard let project else { return }
        ProjectStore.saveDebounced(project)
    }

    func uncertainInCluster(_ cluster: PhotoCluster) -> [PhotoRecord] {
        guard let photos = project?.photos else { return [] }
        let ids = Set(cluster.photoIDs)
        return photos.filter { ids.contains($0.id) && $0.isUncertain }
    }
}
