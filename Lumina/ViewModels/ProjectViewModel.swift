import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ProjectViewModel {
    var project: LuminaProject?
    var selectedPhotoID: UUID?
    var filter: GridFilter = .all
    var statusMessage = "Import a RAW folder to begin."
    var isBusy = false
    var showBefore = false
    var globalAdjustments = DevelopAdjustments.zero

    var selectedPhoto: PhotoRecord? {
        guard let id = selectedPhotoID else { return nil }
        return project?.photos.first { $0.id == id }
    }

    var filteredPhotos: [PhotoRecord] {
        guard let photos = project?.photos else { return [] }
        switch filter {
        case .all: return photos
        case .keeps: return photos.filter { $0.tier == .keep }
        case .rejects: return photos.filter { $0.tier == .reject }
        case .flagged: return photos.filter { $0.isFlagged }
        }
    }

    var keepCount: Int {
        project?.photos.filter { $0.tier == .keep }.count ?? 0
    }

    var totalCount: Int {
        project?.photos.count ?? 0
    }

    var flaggedCount: Int {
        project?.photos.filter { $0.isFlagged }.count ?? 0
    }

    func importFolders(rawURL: URL, jpgURL: URL?) async {
        isBusy = true
        defer { isBusy = false }

        do {
            guard ExifToolService.isAvailable else {
                statusMessage = "Install exiftool: brew install exiftool"
                return
            }

            let imported = try await ImportPipeline.importProject(
                rawFolder: rawURL,
                jpgFolder: jpgURL,
                keepRate: project?.keepRateTarget ?? 0.10
            ) { message in
                await MainActor.run { self.statusMessage = message }
            }

            project = imported
            globalAdjustments = .zero
            filter = imported.photos.contains(where: \.isFlagged) ? .flagged : .keeps
            selectedPhotoID = filteredPhotos.first?.id ?? imported.photos.first?.id
            statusMessage = "Imported \(imported.photos.count) photos · \(keepCount) keeps · \(flaggedCount) need you"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setTier(_ tier: PhotoTier, for photoID: UUID) {
        guard var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == photoID }) else { return }
        project.photos[index].tier = tier
        project.photos[index].isFlagged = tier == .maybe
        self.project = project
        persist()
    }

    func markKeep() {
        guard let id = selectedPhotoID else { return }
        setTier(.keep, for: id)
        advanceFlag()
    }

    func markReject() {
        guard let id = selectedPhotoID else { return }
        setTier(.reject, for: id)
        advanceFlag()
    }

    func markMaybe() {
        guard let id = selectedPhotoID else { return }
        setTier(.maybe, for: id)
    }

    func advanceFlag() {
        guard filter == .flagged else {
            selectNext(in: filteredPhotos)
            return
        }
        let flags = project?.photos.filter(\.isFlagged) ?? []
        guard let current = selectedPhotoID,
              let index = flags.firstIndex(where: { $0.id == current }) else {
            selectNext(in: flags)
            return
        }
        let nextIndex = min(index + 1, flags.count - 1)
        if nextIndex < flags.count {
            selectedPhotoID = flags[nextIndex].id
        } else if let first = flags.first {
            selectedPhotoID = first.id
        }
        statusMessage = "\(flaggedCount) need you · \(keepCount)/\(totalCount) kept"
    }

    func previousFlag() {
        let list = filter == .flagged ? (project?.photos.filter(\.isFlagged) ?? []) : filteredPhotos
        guard let current = selectedPhotoID,
              let index = list.firstIndex(where: { $0.id == current }) else { return }
        let prev = max(index - 1, 0)
        selectedPhotoID = list[prev].id
    }

    func selectNext(in list: [PhotoRecord]) {
        guard let current = selectedPhotoID,
              let index = list.firstIndex(where: { $0.id == current }) else {
            selectedPhotoID = list.first?.id
            return
        }
        let next = min(index + 1, list.count - 1)
        selectedPhotoID = list[next].id
    }

    func applyAdjustmentsToAllKeeps() {
        guard var project else { return }
        for index in project.photos.indices where project.photos[index].tier == .keep {
            project.photos[index].perPhotoAdjustments = globalAdjustments
                .merged(with: DevelopAdjustments.zero) // store offset from profile baseline
        }
        // Store global as project-level adjustment
        project.globalAdjustments = globalAdjustments
        self.project = project
        persist()
        statusMessage = "Applied look to all keeps"
    }

    func exportCarousel() {
        guard let project else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose export folder"
        panel.nameFieldStringValue = project.name

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            let dir = try ExportService.exportCarousel(
                photos: project.photos,
                projectName: project.name,
                profile: project.profile,
                globalAdjustments: globalAdjustments,
                to: folder
            )
            statusMessage = "Exported to \(dir.path)"
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func pickRAWFolder() {
        let raw = pickFolder(message: "Select RAW folder (.ARW)")
        guard let raw else { return }

        let alert = NSAlert()
        alert.messageText = "Import edited JPG folder for taste profile?"
        alert.informativeText = "Optional — Lumina learns your Lightroom look from exported JPGs with embedded XMP."
        alert.addButton(withTitle: "Choose JPG Folder")
        alert.addButton(withTitle: "Skip")

        var jpgURL: URL?
        if alert.runModal() == .alertFirstButtonReturn {
            jpgURL = pickFolder(message: "Select edited JPG folder")
        }

        Task { await importFolders(rawURL: raw, jpgURL: jpgURL) }
    }

    private func pickFolder(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func persist() {
        guard let project else { return }
        try? ProjectStore.save(project)
    }
}
