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
    var showBefore = false
    var compareMix: Double = 1
    var globalAdjustments = DevelopAdjustments.zero
    var softRender = SoftRenderController()
    var activeClusterIndex: Int = 0
    var viewMode: ViewMode = .session
    var groupPhase: GroupPhase = .intro
    var manualPickIDs: Set<UUID> = []

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
        "\(uncertainCount) decisions left"
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
        defer { isBusy = false }

        let stream = ImportPipeline.importProject(
            sourceFolder: sourceFolder,
            photoURLs: photoURLs,
            jpgFolder: jpgURL,
            keepRate: project?.keepRateTarget ?? 0.10
        )

        for await event in stream {
            switch event {
            case .status(let msg):
                statusMessage = msg
            case .photosReady(let photos, let profile):
                let p = LuminaProject(
                    name: sourceFolder.lastPathComponent,
                    rawFolder: sourceFolder.path,
                    jpgFolder: jpgURL?.path,
                    profile: profile,
                    photos: photos
                )
                project = p
                selectedPhotoID = photos.first?.id
                viewMode = .overview
                sortMode = .all
                statusMessage = "Previews ready · grouping in background…"
            case .photosUpdated(let photos):
                project?.photos = photos
            case .finished(let finished):
                project = finished
                globalAdjustments = .zero
                withAnimation(.easeInOut(duration: 0.35)) {
                    sortMode = .similar
                    viewMode = .session
                    activeClusterIndex = 0
                    groupPhase = .intro
                    manualPickIDs = []
                }
                if let hero = reviewClusters.first?.heroID {
                    selectedPhotoID = hero
                } else {
                    selectedPhotoID = finished.photos.first?.id
                }
                let sets = reviewClusters.count
                statusMessage = "Meet your sets · \(sets) groups · swipe through with direction"
            case .failed(let msg):
                statusMessage = msg
            }
        }
    }

    func pickRAWFolder() { pickImportSources() }

    func pickImportSources() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = "Select a folder and/or photo files"
        panel.prompt = "Import"
        panel.allowedContentTypes = MediaFormats.utTypes
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let photos = MediaFormats.collectPhotos(from: panel.urls)
        guard !photos.isEmpty else {
            statusMessage = "No importable photos in that selection."
            return
        }

        let sourceFolder: URL
        if panel.urls.count == 1, panel.urls[0].hasDirectoryPath {
            sourceFolder = panel.urls[0]
        } else {
            sourceFolder = photos[0].deletingLastPathComponent()
        }

        let alert = NSAlert()
        alert.messageText = "Use a Lightroom JPG folder for taste?"
        alert.informativeText = "Optional — learns your look from edited JPGs."
        alert.addButton(withTitle: "Choose Folder")
        alert.addButton(withTitle: "Skip")

        var jpgURL: URL?
        if alert.runModal() == .alertFirstButtonReturn {
            jpgURL = pickFolder(message: "Select edited JPG folder")
        }

        let explicitFiles = panel.urls.contains(where: { !$0.hasDirectoryPath }) ? photos : nil
        Task { await importPhotos(sourceFolder: sourceFolder, photoURLs: explicitFiles, jpgURL: jpgURL) }
    }

    // MARK: - Selection

    func selectPhoto(_ id: UUID) {
        selectedPhotoID = id
        if groupPhase == .decide || viewMode == .overview {
            playSoftRender(for: id)
        } else {
            softRender.mix = 1
        }
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

    func setTier(_ tier: PhotoTier, for photoID: UUID) {
        guard var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == photoID }) else { return }
        project.photos[index].tier = tier
        project.photos[index].isFlagged = false
        project.photos[index].uncertaintyKind = .none
        project.photos[index].whyUncertain = nil
        project.photos[index].cullConfidence = 1
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
        project.photos[index].isBurstHero = true
        project.photos[index].isClusterHero = true
        project.photos[index].tier = .keep
        project.photos[index].isFlagged = false
        project.photos[index].uncertaintyKind = .none
        self.project = project
        persistDebounced()
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

    func advanceCluster() {
        let all = reviewClusters
        guard !all.isEmpty else {
            groupPhase = .done
            return
        }
        if activeClusterIndex >= all.count - 1 {
            withAnimation { groupPhase = .done }
            statusMessage = "Session clear · \(keepCount) keeps"
            return
        }
        activeClusterIndex += 1
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

    func uncertainInCluster(_ cluster: PhotoCluster) -> [PhotoRecord] {
        guard let photos = project?.photos else { return [] }
        let ids = Set(cluster.photoIDs)
        return photos.filter { ids.contains($0.id) && $0.isUncertain }
    }

    // MARK: - Export

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
        statusMessage = "Exporting collections…"
        let snapshot = project
        let adjustments = globalAdjustments

        Task {
            do {
                let dir = try await ExportService.exportCollections(
                    project: snapshot,
                    globalAdjustments: adjustments,
                    aspects: [.fourByFive, .nineBySixteen],
                    writeXMP: true,
                    to: folder
                ) { [weak self] msg in
                    Task { @MainActor in self?.statusMessage = msg }
                }
                await MainActor.run {
                    self.isBusy = false
                    self.statusMessage = "Exported to \(dir.path)"
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func applyAdjustmentsToAllKeeps() {
        guard var project else { return }
        for index in project.photos.indices where project.photos[index].tier == .keep {
            if var recipe = project.photos[index].recipe {
                recipe = recipe.applying(globalAdjustments)
                project.photos[index].recipe = recipe
            }
            project.photos[index].perPhotoAdjustments = .zero
        }
        project.globalAdjustments = globalAdjustments
        self.project = project
        persistDebounced()
        statusMessage = "Applied slider offsets to all keeps"
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
}
