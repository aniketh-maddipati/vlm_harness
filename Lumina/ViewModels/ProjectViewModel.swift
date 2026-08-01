import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ProjectViewModel {
    var project: LuminaProject?
    var selectedPhotoID: UUID?
    var sortMode: SortMode = .uncertain
    var filter: GridFilter = .all
    var statusMessage = "Import photos to begin."
    var isBusy = false
    var showBefore = false
    var compareMix: Double = 1
    var globalAdjustments = DevelopAdjustments.zero
    var softRender = SoftRenderController()
    var activeClusterIndex: Int = 0
    var viewMode: ViewMode = .uncertain

    enum ViewMode: String, CaseIterable {
        case uncertain = "Uncertain"
        case cluster = "Clusters"
        case grid = "Grid"
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

    var clusters: [PhotoCluster] {
        guard let photos = project?.photos else { return [] }
        return CullEngine.clusters(from: photos)
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
                viewMode = .grid
                sortMode = .all
            case .photosUpdated(let photos):
                project?.photos = photos
            case .finished(let finished):
                project = finished
                globalAdjustments = .zero
                sortMode = finished.photos.contains(where: \.isUncertain) ? .uncertain : .quality
                viewMode = sortMode == .uncertain ? .uncertain : .cluster
                selectedPhotoID = displayedPhotos.first?.id ?? finished.photos.first?.id
                if let id = selectedPhotoID {
                    playSoftRender(for: id)
                }
                statusMessage = "Imported \(finished.photos.count) · \(keepCount) keeps · \(uncertainCount) uncertain"
            case .failed(let msg):
                statusMessage = msg
            }
        }
    }

    func pickRAWFolder() {
        pickImportSources()
    }

    func pickImportSources() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.message = "Select a folder and/or photo files (RAW, JPG, HEIC, PNG, TIFF…)"
        panel.prompt = "Import"
        panel.allowedContentTypes = MediaFormats.utTypes
        // Still allow any file — ImageIO will decide if it's readable
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
        alert.messageText = "Import edited JPG folder for taste profile?"
        alert.informativeText = "Optional — builds per-photo taste retrieval from Lightroom XMP."
        alert.addButton(withTitle: "Choose JPG Folder")
        alert.addButton(withTitle: "Skip")

        var jpgURL: URL?
        if alert.runModal() == .alertFirstButtonReturn {
            jpgURL = pickFolder(message: "Select edited JPG folder")
        }

        let explicitFiles = panel.urls.contains(where: { !$0.hasDirectoryPath }) ? photos : nil
        Task { await importPhotos(sourceFolder: sourceFolder, photoURLs: explicitFiles, jpgURL: jpgURL) }
    }

    // MARK: - Selection & soft render

    func selectPhoto(_ id: UUID) {
        selectedPhotoID = id
        playSoftRender(for: id)
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
        advanceUncertain()
    }

    func markReject() {
        guard let id = selectedPhotoID else { return }
        setTier(.reject, for: id)
        advanceUncertain()
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
        advanceUncertain()
    }

    func advanceUncertain() {
        let list = uncertainPhotos
        guard let current = selectedPhotoID,
              let index = list.firstIndex(where: { $0.id == current }) else {
            selectedPhotoID = list.first?.id
            return
        }
        let next = index + 1
        if next < list.count {
            selectPhoto(list[next].id)
        } else if let first = list.first {
            selectPhoto(first.id)
        }
        statusMessage = decisionBudgetText + " · \(keepCount)/\(totalCount) kept"
    }

    func previousUncertain() {
        let list = sortMode == .uncertain ? uncertainPhotos : displayedPhotos
        guard let current = selectedPhotoID,
              let index = list.firstIndex(where: { $0.id == current }) else { return }
        selectPhoto(list[max(index - 1, 0)].id)
    }

    func advanceCluster() {
        let all = clusters
        guard !all.isEmpty else { return }
        activeClusterIndex = min(activeClusterIndex + 1, all.count - 1)
        if let hero = all[activeClusterIndex].heroID {
            selectPhoto(hero)
        }
    }

    func previousCluster() {
        let all = clusters
        guard !all.isEmpty else { return }
        activeClusterIndex = max(activeClusterIndex - 1, 0)
        if let hero = all[activeClusterIndex].heroID {
            selectPhoto(hero)
        }
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
