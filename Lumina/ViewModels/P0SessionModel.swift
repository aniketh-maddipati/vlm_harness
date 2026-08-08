import AppKit
import Foundation
import Observation
import SwiftUI

enum P0Route: Equatable {
    case open
    case contactSheet
}

/// Orthogonal visual marks derived from canonical state.
struct ContactSheetMarks: Equatable {
    var unreviewed: Bool
    var kept: Bool
    var rejected: Bool
    var selected: Bool
    var edited: Bool
    /// 1-based order index when kept-order mode is on; nil otherwise.
    var orderIndex: Int?

    static func derive(
        asset: AssetRecord,
        selectedIDs: Set<UUID>,
        orderedIDs: [UUID],
        keptOrderMode: Bool
    ) -> ContactSheetMarks {
        let orderIndex: Int?
        if keptOrderMode, let idx = orderedIDs.firstIndex(of: asset.id) {
            orderIndex = idx + 1
        } else {
            orderIndex = nil
        }
        return ContactSheetMarks(
            unreviewed: asset.cull == .undecided || asset.cull == .hold,
            kept: asset.cull == .keep,
            rejected: asset.cull == .reject,
            selected: selectedIDs.contains(asset.id),
            edited: asset.recipe != nil,
            orderIndex: orderIndex
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
    /// One-shot flag so returning from single-photo restores scroll without fighting live browsing.
    var pendingScrollRestore = false
    let undoCoordinator = P0UndoCoordinator()

    private var preparationTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var folderAccess: (url: URL, didStartAccess: Bool)?

    var selectionCount: Int { selectedAssetIDs.count }

    var keptCount: Int { assets.filter { $0.cull == .keep }.count }

    /// Export count is always derived from the complete kept set.
    var exportCount: Int { keptCount }

    var keptOrderMode: Bool { shoot?.workspace.keptOrderMode ?? false }

    var orderedIDList: [UUID] {
        shoot?.finalSetOrder.assetIDs ?? []
    }

    var orderedIDSet: Set<UUID> {
        Set(orderedIDList)
    }

    var canUndo: Bool { undoCoordinator.canUndo }

    var visibleItems: [ContactSheetItem] {
        let ordered = orderedIDList
        let selected = selectedAssetIDs
        let orderMode = keptOrderMode
        return filteredAssets.map { asset in
            ContactSheetItem(
                asset: asset,
                aspectRatio: ContactSheetPreparation.aspectRatio(for: asset),
                marks: .derive(
                    asset: asset,
                    selectedIDs: selected,
                    orderedIDs: ordered,
                    keptOrderMode: orderMode
                )
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

    var preparationLine: String {
        var line = status.toolbarLine
        if keptCount > 0 {
            line += " · \(keptCount) kept"
        }
        return line
    }

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
        undoCoordinator.clear()

        let started = url.startAccessingSecurityScopedResource()
        folderAccess = (url, started)

        preparationTask = Task { [weak self] in
            guard let self else { return }
            let stream = ContactSheetPreparation.openFolder(url)
            await self.consume(stream)
        }
    }

    func openRecent(_ summary: RecentShootSummary) {
        openShoot(named: summary.name)
    }

    /// Open an existing shoot by name (used by Recent, and by the DEBUG UI-test auto-open path,
    /// which must not depend on the recent-shoots list being populated yet).
    func openShoot(named name: String) {
        preparationTask?.cancel()
        releaseFolderAccess()
        userFacingError = nil
        inspectingAssetID = nil
        selectedAssetIDs = []
        focusedAssetID = nil
        undoCoordinator.clear()

        preparationTask = Task { [weak self] in
            guard let self else { return }
            let stream = ContactSheetPreparation.openExisting(shootName: name)
            await self.consume(stream)
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        FileDropResolver.collectURLs(from: providers, requireFileURLType: false) { [weak self] urls in
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

    // MARK: - Cull (P / X)

    /// Keep focused photograph. Repeat clears to unreviewed. Never touches recipe/selection/AI.
    func pressKeep() {
        applyCullToggle(pressed: .keep)
    }

    /// Reject focused photograph. Repeat clears to unreviewed. Rejected stay visible.
    func pressReject() {
        applyCullToggle(pressed: .reject)
    }

    func undoLastCull() {
        guard let command = undoCoordinator.popCull() else { return }
        let selectionSnapshot = selectedAssetIDs
        guard let index = assets.firstIndex(where: { $0.id == command.assetID }) else { return }

        assets[index].cull = command.before
        assets[index].userDecidedAt = command.before == .undecided ? nil : Date()
        if var shoot {
            shoot.finalSetOrder.assetIDs = command.finalOrderBefore
            shoot.assets = assets
            self.shoot = shoot
        }
        selectedAssetIDs = selectionSnapshot
        persistShootImmediately()
    }

    private func applyCullToggle(pressed: CullDecision) {
        guard let focusID = focusedAssetID ?? inspectingAssetID,
              let index = assets.firstIndex(where: { $0.id == focusID }) else { return }

        let selectionSnapshot = selectedAssetIDs
        let recipeBefore = assets[index].recipe
        let before = assets[index].cull
        let after = CullMutationCommand.resolveToggle(current: before, pressed: pressed)
        guard before != after else { return }

        let orderBefore = shoot?.finalSetOrder.assetIDs ?? []

        assets[index].cull = after
        assets[index].userDecidedAt = after == .undecided ? nil : Date()
        // Hard invariant: cull never mutates edit state.
        assets[index].recipe = recipeBefore

        var orderAfter = orderBefore
        if var shoot {
            var order = shoot.finalSetOrder
            let keptIDs = assets.filter { $0.cull == .keep }.map(\.id)
            order.reconcileKeptMembership(keptIDsInChronologicalOrder: keptIDs)
            orderAfter = order.assetIDs
            shoot.finalSetOrder = order
            shoot.assets = assets
            self.shoot = shoot
        }

        selectedAssetIDs = selectionSnapshot

        let command = CullMutationCommand(
            assetID: focusID,
            before: before,
            after: after,
            finalOrderBefore: orderBefore,
            finalOrderAfter: orderAfter
        )
        undoCoordinator.push(command)
        persistShootImmediately()
    }

    // MARK: - Focus / selection

    func setFocus(_ id: UUID?) {
        let start = CFAbsoluteTimeGetCurrent()
        focusedAssetID = id
        if inspectingAssetID != nil, let id {
            inspectingAssetID = id
        }
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
        if inspectingAssetID != nil {
            let current = focusedAssetID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? 0
            let next = min(max(current + dx + dy * max(columns, 1), 0), items.count - 1)
            setFocus(items[next].id)
            return
        }
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
        schedulePersistRestore()
        inspectingAssetID = id
        focusedAssetID = id
        persistRestoreNow()
    }

    func closeInspection() {
        pendingScrollRestore = true
        inspectingAssetID = nil
        persistRestoreNow()
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
        undoCoordinator.clear()
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
            let cullByID = Dictionary(uniqueKeysWithValues: self.assets.map { ($0.id, $0.cull) })
            var merged = assets
            for i in merged.indices {
                if let cull = cullByID[merged[i].id] {
                    merged[i].cull = cull
                }
            }
            self.assets = merged
            self.shoot?.assets = merged
            self.status = status
            if let focus, merged.contains(where: { $0.id == focus }) {
                focusedAssetID = focus
            }
            selectedAssetIDs = selection.intersection(Set(merged.map(\.id)))
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
            if let existing = map[asset.id] {
                var merged = asset
                merged.cull = existing.cull
                merged.recipe = existing.recipe
                map[asset.id] = merged
            } else {
                map[asset.id] = asset
            }
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
        pendingScrollRestore = workspace.scrollAnchor != nil
        if let focused = workspace.focusedAssetID,
           assets.contains(where: { $0.id == focused }) {
            focusedAssetID = focused
        } else {
            focusedAssetID = assets.first?.id
        }
        if workspace.scale == .singlePhoto, let focusedAssetID {
            inspectingAssetID = focusedAssetID
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

    /// Cull mutations persist immediately — not wait for restore debounce.
    private func persistShootImmediately() {
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
        let snapshot = shoot
        Task {
            try? await ShootStore.shared.saveShoot(snapshot)
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
