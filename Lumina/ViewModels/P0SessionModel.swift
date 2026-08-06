import AppKit
import Foundation
import Observation
import SwiftUI

enum P0Route: Equatable {
    case open
    case contactSheet
}

/// Orthogonal visual marks derived from canonical state — slots only; no P/X mutations here.
struct ContactSheetMarks: Equatable {
    var unreviewed: Bool
    var kept: Bool
    var rejected: Bool
    var selected: Bool
    var edited: Bool
    var ordered: Bool

    static func derive(asset: AssetRecord, selectedIDs: Set<UUID>, orderedIDs: Set<UUID>) -> ContactSheetMarks {
        ContactSheetMarks(
            unreviewed: asset.cull == .undecided || asset.cull == .hold,
            kept: asset.cull == .keep,
            rejected: asset.cull == .reject,
            selected: selectedIDs.contains(asset.id),
            edited: asset.recipe != nil,
            ordered: orderedIDs.contains(asset.id)
        )
    }
}

struct ContactSheetItem: Identifiable, Equatable {
    var id: UUID { asset.id }
    var asset: AssetRecord
    var aspectRatio: CGFloat
    var marks: ContactSheetMarks
}

/// P0 session: open a shoot → incremental contact sheet. Does not drive Workbench/Canvas.
@MainActor
@Observable
final class P0SessionModel {
    var route: P0Route = .open
    var shoot: ShootRecord?
    var assets: [AssetRecord] = []
    var status = ContactSheetPreparationStatus()
    var recentShoots: [RecentShootSummary] = []
    var focusedAssetID: UUID?
    var selectedAssetIDs: Set<UUID> = []
    var densityColumns: Int = 6
    var filter: GridFilter = .all
    var scrollAnchor: Double = 0
    var userFacingError: String?
    var isDropTargeted = false
    /// Single-photo placeholder — opens on Return / double-click; editing rail is a later checkpoint.
    var inspectingAssetID: UUID?
    var showLegacyShell = false

    private var preparationTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var folderAccess: (url: URL, didStartAccess: Bool)?

    var selectionCount: Int { selectedAssetIDs.count }

    var orderedIDSet: Set<UUID> {
        Set(shoot?.finalSetOrder.assetIDs ?? [])
    }

    var visibleItems: [ContactSheetItem] {
        let ordered = orderedIDSet
        let selected = selectedAssetIDs
        return filteredAssets.map { asset in
            ContactSheetItem(
                asset: asset,
                aspectRatio: ContactSheetPreparation.aspectRatio(for: asset),
                marks: .derive(asset: asset, selectedIDs: selected, orderedIDs: ordered)
            )
        }
    }

    var filteredAssets: [AssetRecord] {
        switch filter {
        case .all:
            return assets
        case .keeps:
            return assets.filter { $0.cull == .keep }
        case .rejects:
            return assets.filter { $0.cull == .reject }
        case .flagged:
            return assets.filter { $0.isFlagged || $0.cull == .hold }
        }
    }

    var preparationLine: String { status.toolbarLine }

    init() {
        refreshRecent()
    }

    func refreshRecent() {
        recentShoots = (try? ShootStore.listRecentShoots()) ?? []
    }

    // MARK: - Open

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of photographs"
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(url)
    }

    func openFolder(_ url: URL) {
        preparationTask?.cancel()
        releaseFolderAccess()
        userFacingError = nil
        inspectingAssetID = nil
        selectedAssetIDs = []
        focusedAssetID = nil

        let started = url.startAccessingSecurityScopedResource()
        folderAccess = (url, started)

        preparationTask = Task { [weak self] in
            guard let self else { return }
            let stream = ContactSheetPreparation.openFolder(url)
            await self.consume(stream)
        }
    }

    func openRecent(_ summary: RecentShootSummary) {
        preparationTask?.cancel()
        releaseFolderAccess()
        userFacingError = nil
        inspectingAssetID = nil
        selectedAssetIDs = []
        focusedAssetID = nil

        preparationTask = Task { [weak self] in
            guard let self else { return }
            let stream = ContactSheetPreparation.openExisting(shootName: summary.name)
            await self.consume(stream)
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, let root = Self.scanRoot(from: urls) else { return }
            self.openFolder(root)
        }
        return true
    }

    func ingestDroppedURLs(_ urls: [URL]) {
        guard let root = Self.scanRoot(from: urls) else {
            userFacingError = "No importable photos in drop."
            return
        }
        openFolder(root)
    }

    // MARK: - Focus / selection

    func setFocus(_ id: UUID?) {
        let start = CFAbsoluteTimeGetCurrent()
        focusedAssetID = id
        if let id, let asset = assets.first(where: { $0.id == id }),
           let path = asset.gridThumbPath ?? asset.thumbPath {
            ThumbCache.shared.prefetch(path)
            LatencyMetrics.record(
                "p0.focus_to_preview",
                milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000
            )
        }
        schedulePersistRestore()
    }

    func moveFocus(dx: Int, dy: Int, columns: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let cols = max(columns, 1)
        let current = focusedAssetID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? 0
        let row = current / cols
        let col = current % cols
        let newRow = max(0, row + dy)
        let newCol = min(max(0, col + dx), cols - 1)
        var next = newRow * cols + newCol
        if next >= items.count { next = items.count - 1 }
        setFocus(items[next].id)
    }

    func selectClick(id: UUID, command: Bool, shift: Bool) {
        if shift, let anchor = focusedAssetID ?? selectedAssetIDs.first,
           let a = visibleItems.firstIndex(where: { $0.id == anchor }),
           let b = visibleItems.firstIndex(where: { $0.id == id }) {
            let range = a <= b ? a...b : b...a
            selectedAssetIDs = Set(visibleItems[range].map(\.id))
        } else if command {
            if selectedAssetIDs.contains(id) {
                selectedAssetIDs.remove(id)
            } else {
                selectedAssetIDs.insert(id)
            }
        } else {
            selectedAssetIDs = [id]
        }
        setFocus(id)
    }

    func openFocusedPhotograph() {
        guard let id = focusedAssetID ?? selectedAssetIDs.first else { return }
        inspectingAssetID = id
        // Single-photo editing rail is the next checkpoint — placeholder only.
    }

    func closeInspection() {
        inspectingAssetID = nil
    }

    func adjustDensity(_ delta: Int) {
        densityColumns = min(12, max(2, densityColumns + delta))
        schedulePersistRestore()
    }

    func setScrollAnchor(_ value: Double) {
        scrollAnchor = min(max(value, 0), 1)
        schedulePersistRestore()
    }

    func setFilter(_ filter: GridFilter) {
        self.filter = filter
        schedulePersistRestore()
    }

    func goHome() {
        preparationTask?.cancel()
        persistRestoreNow()
        releaseFolderAccess()
        shoot = nil
        assets = []
        status = ContactSheetPreparationStatus()
        focusedAssetID = nil
        selectedAssetIDs = []
        inspectingAssetID = nil
        route = .open
        refreshRecent()
    }

    // MARK: - Consume preparation

    private func consume(_ stream: AsyncStream<ContactSheetEvent>) async {
        for await event in stream {
            guard !Task.isCancelled else { return }
            apply(event)
        }
    }

    private func apply(_ event: ContactSheetEvent) {
        switch event {
        case .opened(let shoot, let status):
            self.shoot = shoot
            self.assets = shoot.assets
            self.status = status
            restoreWorkspace(from: shoot.workspace)
            route = .contactSheet
        case .assetsReplaced(let assets, let status):
            let focus = focusedAssetID
            let selection = selectedAssetIDs
            self.assets = assets
            self.shoot?.assets = assets
            self.status = status
            focusedAssetID = focus.flatMap { id in assets.contains(where: { $0.id == id }) ? id : nil } ?? focus
            selectedAssetIDs = selection.intersection(Set(assets.map(\.id)))
        case .assetsInserted(let assets, let status):
            mergeAssets(assets)
            self.status = status
        case .previewsUpdated(let assets, let status):
            mergePreviewFields(from: assets)
            self.status = status
        case .metadataMerged(let assets, let status):
            let focus = focusedAssetID
            let selection = selectedAssetIDs
            self.assets = assets
            self.shoot?.assets = assets
            self.status = status
            // Identity / selection / focus survive reorder.
            if let focus, assets.contains(where: { $0.id == focus }) {
                focusedAssetID = focus
            }
            selectedAssetIDs = selection.intersection(Set(assets.map(\.id)))
        case .status(let status):
            self.status = status
        case .failed(let message):
            userFacingError = message
            status.phaseDetail = message
        }
    }

    private func mergeAssets(_ incoming: [AssetRecord]) {
        var map = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        for asset in incoming {
            map[asset.id] = asset
        }
        assets = map.values.sorted(by: ContactSheetPreparation.chronologicalLess)
        shoot?.assets = assets
    }

    private func mergePreviewFields(from incoming: [AssetRecord]) {
        let byID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        for i in assets.indices {
            guard let updated = byID[assets[i].id] else { continue }
            assets[i].thumbPath = updated.thumbPath
            assets[i].gridThumbPath = updated.gridThumbPath
            assets[i].previewOrigin = updated.previewOrigin
            assets[i].previewLongEdge = updated.previewLongEdge
            assets[i].source.availability = updated.source.availability
        }
        shoot?.assets = assets
    }

    private func restoreWorkspace(from workspace: WorkspaceRestoreState) {
        filter = workspace.filter
        if let density = workspace.contactSheetDensity {
            densityColumns = min(12, max(2, density))
        }
        scrollAnchor = workspace.scrollAnchor ?? 0
        if let focused = workspace.focusedAssetID,
           assets.contains(where: { $0.id == focused }) {
            focusedAssetID = focused
        } else {
            focusedAssetID = assets.first?.id
        }
    }

    private func schedulePersistRestore() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.persistRestoreNow() }
        }
    }

    private func persistRestoreNow() {
        guard var shoot else { return }
        shoot.workspace = WorkspaceRestoreState(
            focusedAssetID: focusedAssetID,
            filter: filter,
            contactSheetDensity: densityColumns,
            scrollAnchor: scrollAnchor,
            scale: inspectingAssetID == nil ? .contactSheet : .singlePhoto,
            keptOrderMode: shoot.workspace.keptOrderMode
        )
        shoot.assets = assets
        self.shoot = shoot
        Task {
            await ShootStore.shared.saveShootDebounced(shoot)
        }
    }

    private func releaseFolderAccess() {
        if let folderAccess {
            SecurityScopedAccess.stopIfNeeded(folderAccess.url, didStartAccess: folderAccess.didStartAccess)
        }
        folderAccess = nil
    }

    private static func scanRoot(from urls: [URL]) -> URL? {
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue { return url }
            if MediaFormats.isImportable(url) { return url.deletingLastPathComponent() }
        }
        return nil
    }
}
