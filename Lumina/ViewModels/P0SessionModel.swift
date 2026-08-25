import AppKit
import CoreImage
import Foundation
import Observation
import SwiftUI

enum P0Route: Equatable {
    case open
    case contactSheet
    /// Bridge into grouping — cull/selection state stays intact; full grouping is next.
    case grouping
}

enum P0AdjustmentSection: String, CaseIterable, Identifiable, Sendable {
    case light
    case color
    case detail
    case crop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .color: return "Color"
        case .detail: return "Detail"
        case .crop: return "Crop"
        }
    }
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
            edited: asset.recipe?.hasSettings == true,
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
    /// Time-rail chapter currently on the board. Nil until a shoot has photographs.
    var activeChapterID: String?
    var selectedAssetIDs: Set<UUID> = []
    var densityColumns: Int = 6
    /// Density is a lean. Rest state packs to leftover height.
    var densityLeaned: Bool = false
    /// Hold-Space loupe — release returns.
    var holdingLoupe: Bool = false
    /// Hold-J clipping glance — release returns.
    var holdingClipping: Bool = false
    /// Hold-⌘G look glance — release returns to time.
    var lookGlancing: Bool = false
    var glanceBurstIDs: [String] = []
    /// Return / pinch opens a multi-frame burst to pick a frame.
    var leanedBurstID: String?
    /// Tab / click walks the kept rail instead of the chapter.
    var walkingKeptRail: Bool = false
    var travelingBurstID: String?
    var filter: GridFilter = .all
    var scrollAnchor: Double = 0
    var userFacingError: String?
    var isDropTargeted = false
    /// Single-photo editing surface — opens on Return / double-click.
    var inspectingAssetID: UUID?
    var showLegacyShell = false
    /// One-shot flag so returning from single-photo restores scroll without fighting live browsing.
    var pendingScrollRestore = false
    let undoCoordinator = P0UndoCoordinator()
    /// RAW develop scheduler — created on first edit entry, released when leaving a shoot.
    private var developSchedulerStorage: DevelopRenderScheduler?
    /// Working recipe while a slider/crop gesture is active (authoritative only after commit).
    private(set) var workingRecipe: EditRecipe?
    private(set) var gestureBaselineRecipe: EditRecipe?
    private(set) var gestureAssetID: UUID?
    private(set) var isEditGestureActive = false
    /// Press-and-hold Before — never mutates recipe or undo.
    var showingBefore = false
    var expandedAdjustmentSection: P0AdjustmentSection? = .light
    var rawCapabilities: PreparedRawSession.Capabilities?
    var rawNativeTemperature: Double?
    var rawNativeTint: Double?
    var fidelityNotice: String?
    private(set) var editMetricsLine: String = ""

    private var preparationTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var shootPersistTask: Task<Void, Never>?
    private var folderAccess: (url: URL, didStartAccess: Bool)?
    private var capabilityTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    /// Debounces expensive settle/prewarm while arrow keys / filmstrip hover spam focus.
    private var inspectionWarmTask: Task<Void, Never>?
    private var inspectionWarmGeneration = 0
    private var scrubInputStartedAt: CFAbsoluteTime?
    /// Managed-field hash Lumina last wrote per asset — drift detection domain (CP2 sidecars).
    private var sidecarManagedHashes: [UUID: String] = [:]
    private(set) var sidecarDriftAssetIDs: Set<UUID> = []
    /// Cull hot-loop grammar — sole authority for mark/focus/advance (CP4 / D10 / D59).
    private var cullGrammar = CullGrammarMachine(assetCount: 0)

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

    var undoLabel: String? { undoCoordinator.undoLabel }

    /// Canonical recipe for the focused/inspected photograph (nil → neutral).
    func recipe(for assetID: UUID) -> EditRecipe {
        if gestureAssetID == assetID, let workingRecipe {
            return workingRecipe
        }
        return assets.first(where: { $0.id == assetID })?.recipe ?? .neutral
    }

    func displayedCIImage(for assetID: UUID) -> CIImage? {
        guard let developSchedulerStorage else { return nil }
        if showingBefore {
            return developSchedulerStorage.beforeImage(for: assetID)
                ?? developSchedulerStorage.presentedCIImage(for: assetID)
        }
        return developSchedulerStorage.presentedCIImage(for: assetID)
    }

    /// Live develop fidelity for a photograph, if the scheduler has started.
    func developFidelity(for assetID: UUID) -> DevelopFidelityState? {
        developSchedulerStorage?.fidelityByPhoto[assetID]
    }

    var chapters: [ShootChapter] {
        ShootChapterArrangement.arrange(assets)
    }

    var activeChapter: ShootChapter? {
        if let activeChapterID,
           let match = chapters.first(where: { $0.id == activeChapterID }) {
            return match
        }
        return chapters.first
    }

    var visibleItems: [ContactSheetItem] {
        let ordered = orderedIDList
        let selected = selectedAssetIDs
        let orderMode = keptOrderMode
        return boardAssets.map { asset in
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

    /// Inspect walks the whole shoot. The board shows one chapter.
    private var boardAssets: [AssetRecord] {
        if inspectingAssetID != nil {
            return filteredAssets
        }
        guard let chapter = activeChapter else { return filteredAssets }
        let members = Set(chapter.assetIDs)
        return filteredAssets.filter { members.contains($0.id) }
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

    private var developScheduler: DevelopRenderScheduler {
        if let developSchedulerStorage { return developSchedulerStorage }
        let created = DevelopRenderScheduler()
        developSchedulerStorage = created
        return created
    }

    private func releaseDevelopScheduler() {
        developSchedulerStorage?.cancelAll()
        developSchedulerStorage = nil
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
        showingBefore = false
        clearGestureState()
        undoCoordinator.clear()
        releaseDevelopScheduler()
        sidecarManagedHashes = [:]
        sidecarDriftAssetIDs = []

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
        showingBefore = false
        clearGestureState()
        undoCoordinator.clear()
        releaseDevelopScheduler()
        sidecarManagedHashes = [:]
        sidecarDriftAssetIDs = []

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

    // MARK: - Cull (P / X) — routed through CullGrammarMachine (ADOPT / CP4)

    /// Keep focused photograph. Repeat clears to unreviewed. Never touches recipe/selection/AI.
    func pressKeep() {
        applyCullGrammarEvent(.markKeep)
    }

    /// Reject focused photograph. Repeat clears to unreviewed. Rejected stay visible.
    func pressReject() {
        applyCullGrammarEvent(.markReject)
    }

    /// Pointer ✓ target (D47 / A3) — same grammar as `P`, no hover path.
    func pointerMarkKeep() {
        applyCullGrammarEvent(.pointerMarkKeep)
    }

    /// Pointer ✕ target (D47 / A3) — same grammar as `X`, no hover path.
    func pointerMarkReject() {
        applyCullGrammarEvent(.pointerMarkReject)
    }

    func undoLast() {
        flushPendingEditIfNeeded()
        guard let entry = undoCoordinator.pop() else { return }
        switch entry {
        case .cull(let command):
            applyCullUndo(command)
            installCullGrammarFromSession()
        case .edit(let command):
            applyEditUndo(command)
        case .chapterKeep(let command):
            applyChapterKeepUndo(command)
            installCullGrammarFromSession()
        }
    }

    /// Compatibility alias — shared stack now undoes edit or cull.
    func undoLastCull() {
        undoLast()
    }

    private func applyCullUndo(_ command: CullMutationCommand) {
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

    /// Install machine state from visible grid + session marks (coordinator owns undo depth).
    private func installCullGrammarFromSession() {
        let ids = visibleItems.map(\.id)
        guard !ids.isEmpty else {
            cullGrammar = CullGrammarMachine(assetCount: 0)
            return
        }
        var marks: [UUID: CullDecision] = [:]
        for id in ids {
            marks[id] = assets.first(where: { $0.id == id })?.cull ?? .undecided
        }
        let focusIndex: Int
        if let fid = focusedAssetID ?? inspectingAssetID,
           let idx = ids.firstIndex(of: fid) {
            focusIndex = idx
        } else {
            focusIndex = 0
        }
        let state = CullGrammarState(
            assetIDs: ids,
            columnsPerRow: max(densityColumns, 1),
            marks: marks,
            focusIndex: focusIndex,
            staging: cullGrammar.state.staging,
            armedControl: cullGrammar.state.armedControl,
            activeHolds: cullGrammar.state.activeHolds,
            undoStack: []
        )
        cullGrammar = CullGrammarMachine(state: state)
    }

    private func applyCullGrammarEvent(_ event: CullGrammarEvent) {
        installCullGrammarFromSession()
        guard let focusID = focusedAssetID ?? inspectingAssetID,
              let assetIndex = assets.firstIndex(where: { $0.id == focusID }) else { return }

        let selectionSnapshot = selectedAssetIDs
        let recipeBefore = assets[assetIndex].recipe
        let before = assets[assetIndex].cull
        let orderBefore = shoot?.finalSetOrder.assetIDs ?? []
        let wasInspecting = inspectingAssetID != nil

        cullGrammar.apply(event)

        // Single-photo scale: marks commit but focus stays on the inspected frame.
        if wasInspecting {
            switch event {
            case .markKeep, .markReject, .pointerMarkKeep, .pointerMarkReject:
                if let idx = cullGrammar.state.assetIDs.firstIndex(of: focusID) {
                    cullGrammar.apply(.focusIndex(idx))
                }
            default:
                break
            }
        }

        let after = cullGrammar.state.marks[focusID] ?? .undecided
        guard before != after else { return }

        assets[assetIndex].cull = after
        assets[assetIndex].userDecidedAt = after == .undecided ? nil : Date()
        assets[assetIndex].recipe = recipeBefore

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
        journalCullCommit(command)
        schedulePersistShoot()

        if wasInspecting {
            focusedAssetID = focusID
            inspectingAssetID = focusID
        } else if let nextID = cullGrammar.state.focusedAssetID {
            setFocus(nextID)
        }
    }

    private func applyCullToggle(pressed: CullDecision) {
        switch pressed {
        case .keep: applyCullGrammarEvent(.markKeep)
        case .reject: applyCullGrammarEvent(.markReject)
        default: return
        }
    }

    private func applyEditUndo(_ command: EditMutationCommand) {
        let selectionSnapshot = selectedAssetIDs
        let cullSnapshot = assets.first(where: { $0.id == command.assetID })?.cull
        guard let index = assets.firstIndex(where: { $0.id == command.assetID }) else { return }

        assets[index].recipe = command.before.hasSettings ? command.before : nil
        // Hard invariant: edit undo never mutates cull or selection.
        if let cullSnapshot {
            assets[index].cull = cullSnapshot
        }
        selectedAssetIDs = selectionSnapshot
        workingRecipe = nil
        gestureBaselineRecipe = nil
        gestureAssetID = nil
        isEditGestureActive = false
        persistShootImmediately()
        if inspectingAssetID == command.assetID {
            scrubCurrentRecipe(for: command.assetID, recipe: recipe(for: command.assetID), recordInput: false)
        }
    }

    // MARK: - Edit (single-photo)

    func beginEditGesture(for assetID: UUID? = nil) {
        let id = assetID ?? inspectingAssetID ?? focusedAssetID
        guard let id else { return }
        if isEditGestureActive, gestureAssetID == id { return }
        flushPendingEditIfNeeded()
        gestureAssetID = id
        gestureBaselineRecipe = recipe(for: id)
        workingRecipe = gestureBaselineRecipe
        isEditGestureActive = true
        scrubInputStartedAt = CFAbsoluteTimeGetCurrent()
    }

    func scrubEdit(_ mutate: (inout EditRecipe) -> Void) {
        let id = gestureAssetID ?? inspectingAssetID ?? focusedAssetID
        guard let id else { return }
        if !isEditGestureActive || gestureAssetID != id {
            beginEditGesture(for: id)
        }
        let next = (workingRecipe ?? recipe(for: id)).updating(mutate)
        workingRecipe = next
        // Live pixels only — undo commits on gesture end.
        scrubCurrentRecipe(for: id, recipe: next, recordInput: true)
    }

    func endEditGesture() {
        guard isEditGestureActive, let id = gestureAssetID,
              let before = gestureBaselineRecipe,
              let after = workingRecipe else {
            clearGestureState()
            return
        }
        commitRecipeMutation(assetID: id, before: before, after: after)
        settleCurrentRecipe(for: id, recipe: after)
        clearGestureState()
    }

    /// Commit an instantaneous edit (reset, crop preset, rotate) as one undo command.
    func applyEditMutation(_ mutate: (inout EditRecipe) -> Void, assetID: UUID? = nil) {
        flushPendingEditIfNeeded()
        let id = assetID ?? inspectingAssetID ?? focusedAssetID
        guard let id else { return }
        let before = recipe(for: id)
        let after = before.updating(mutate)
        commitRecipeMutation(assetID: id, before: before, after: after)
        scrubCurrentRecipe(for: id, recipe: recipe(for: id), recordInput: false)
        settleCurrentRecipe(for: id, recipe: recipe(for: id))
    }

    func resetRecipeToNeutral(assetID: UUID? = nil) {
        applyEditMutation({ recipe in
            let retainedID = recipe.id
            let neighbors = recipe.sourceNeighbors
            let confidence = recipe.confidence
            recipe = EditRecipe(
                id: retainedID,
                schemaVersion: .current,
                sourceNeighbors: neighbors,
                confidence: confidence
            )
        }, assetID: assetID)
    }

    func resetField(_ keyPath: WritableKeyPath<EditRecipe, Double>, to value: Double = 0) {
        applyEditMutation { $0[keyPath: keyPath] = value }
    }

    func setShowingBefore(_ show: Bool) {
        showingBefore = show
        // Never mutate recipe / undo on Before.
    }

    func flushPendingEditIfNeeded() {
        guard isEditGestureActive else { return }
        endEditGesture()
    }

    private func commitRecipeMutation(assetID: UUID, before: EditRecipe, after: EditRecipe) {
        guard before.valueFingerprint != after.valueFingerprint else { return }
        let selectionSnapshot = selectedAssetIDs
        let cullSnapshot = assets.first(where: { $0.id == assetID })?.cull
        let orderSnapshot = shoot?.finalSetOrder.assetIDs ?? []
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }

        assets[index].recipe = after.hasSettings ? after : nil
        if let cullSnapshot {
            assets[index].cull = cullSnapshot
        }
        if var shoot {
            // Hard invariant: editing never mutates final order.
            shoot.finalSetOrder.assetIDs = orderSnapshot
            shoot.assets = assets
            self.shoot = shoot
        }
        selectedAssetIDs = selectionSnapshot

        let command = EditMutationCommand(assetID: assetID, before: before, after: after)
        undoCoordinator.push(command)
        journalEditCommit(command)
        sidecarEditCommit(command)
        persistShootImmediately()
        warmBeforeAfter(for: assetID, recipe: after.hasSettings ? after : .neutral)
    }

    private func clearGestureState() {
        isEditGestureActive = false
        gestureAssetID = nil
        gestureBaselineRecipe = nil
        workingRecipe = nil
        scrubInputStartedAt = nil
    }

    private func scrubCurrentRecipe(for assetID: UUID, recipe: EditRecipe, recordInput: Bool) {
        guard let urls = resolveRenderURLs(for: assetID) else {
            fidelityNotice = "Original missing — showing cached preview"
            return
        }
        if urls.rawURL == nil {
            fidelityNotice = "Original missing — showing cached preview"
        } else {
            fidelityNotice = nil
        }
        let inputStart = scrubInputStartedAt
        developScheduler.scrub(
            photoID: assetID,
            rawURL: urls.rawURL ?? urls.proxyURL!,
            proxyURL: urls.proxyURL,
            recipe: recipe
        )
        if recordInput, let inputStart,
           developScheduler.presentedCIImage(for: assetID) != nil {
            let ms = (CFAbsoluteTimeGetCurrent() - inputStart) * 1000
            LatencyMetrics.record("p0.edit.slider_to_pixels", milliseconds: ms)
        }
        editMetricsLine = developScheduler.metrics.summaryLine
        LatencyMetrics.record(
            "p0.edit.interactive_ms",
            milliseconds: developScheduler.metrics.lastDurationMs
        )
    }

    private func settleCurrentRecipe(for assetID: UUID, recipe: EditRecipe) {
        guard let urls = resolveRenderURLs(for: assetID) else { return }
        developScheduler.settlePhotograph(
            photoID: assetID,
            rawURL: urls.rawURL ?? urls.proxyURL!,
            proxyURL: urls.proxyURL,
            recipe: recipe
        )
    }

    /// First paint for inspection — settled RAW, not draft interactive.
    private func openRender(for assetID: UUID, recipe: EditRecipe) {
        guard let urls = resolveRenderURLs(for: assetID) else {
            fidelityNotice = "Original missing — showing cached preview"
            return
        }
        if urls.rawURL == nil {
            fidelityNotice = "Original missing — showing cached preview"
        } else {
            fidelityNotice = nil
        }
        developScheduler.openPhotograph(
            photoID: assetID,
            rawURL: urls.rawURL ?? urls.proxyURL!,
            proxyURL: urls.proxyURL,
            recipe: recipe
        )
        editMetricsLine = developScheduler.metrics.summaryLine
    }

    private func warmBeforeAfter(for assetID: UUID, recipe: EditRecipe) {
        guard let urls = resolveRenderURLs(for: assetID), let raw = urls.rawURL else { return }
        Task { [weak self] in
            guard let self else { return }
            let start = CFAbsoluteTimeGetCurrent()
            await self.developScheduler.warmBeforeAfter(
                photoID: assetID,
                rawURL: raw,
                proxyURL: urls.proxyURL,
                recipe: recipe
            )
            LatencyMetrics.record(
                "p0.edit.before_warm_ms",
                milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000
            )
        }
    }

    func prewarmInspection(around assetID: UUID) {
        inspectionWarmGeneration += 1
        let generation = inspectionWarmGeneration
        capabilityTask?.cancel()
        prewarmTask?.cancel()
        showingBefore = false
        refreshCapabilities(for: assetID)
        let recipe = recipe(for: assetID)
        // Leader frame immediately — cancels prior inflight for this photo.
        openRender(for: assetID, recipe: recipe)
        scheduleDebouncedPrewarm(around: assetID, generation: generation, recipe: recipe, delayNanoseconds: 120_000_000)
    }

    /// Focus changed while inspecting — leader render now; neighbor/before-after after pause.
    private func scheduleInspectionWarm(around assetID: UUID) {
        inspectionWarmTask?.cancel()
        inspectionWarmGeneration += 1
        let generation = inspectionWarmGeneration
        capabilityTask?.cancel()
        prewarmTask?.cancel()
        showingBefore = false
        developScheduler.cancelExcept(photoID: assetID)
        let recipe = recipe(for: assetID)
        openRender(for: assetID, recipe: recipe)
        refreshCapabilities(for: assetID)
        inspectionWarmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled, let self else { return }
            guard generation == self.inspectionWarmGeneration,
                  self.inspectingAssetID == assetID else { return }
            self.scheduleDebouncedPrewarm(
                around: assetID,
                generation: generation,
                recipe: recipe,
                delayNanoseconds: 0
            )
        }
    }

    /// Before/After + neighbor settled prewarm — debounced separately from the leader frame.
    private func scheduleDebouncedPrewarm(
        around assetID: UUID,
        generation: Int,
        recipe: EditRecipe,
        delayNanoseconds: UInt64
    ) {
        prewarmTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled, let self else { return }
            guard generation == self.inspectionWarmGeneration,
                  self.inspectingAssetID == assetID else { return }
            self.warmBeforeAfter(for: assetID, recipe: recipe)
            let neighbors = self.neighborIDs(around: assetID, radius: 1)
            let photos: [(UUID, URL)] = neighbors.compactMap { id in
                guard id != assetID,
                      let raw = self.resolveRenderURLs(for: id)?.rawURL else { return nil }
                return (id, raw)
            }
            self.developScheduler.prewarm(photos: photos, recipe: .neutral)
            LatencyMetrics.record("p0.edit.nav_prewarm_count", milliseconds: Double(photos.count))
        }
    }

    private func refreshCapabilities(for assetID: UUID) {
        guard let rawURL = resolveRenderURLs(for: assetID)?.rawURL else {
            rawCapabilities = nil
            rawNativeTemperature = nil
            rawNativeTint = nil
            return
        }
        capabilityTask = Task { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            let session = await PreparedRawSessionRegistry.shared.session(for: assetID, rawURL: rawURL)
            let report = await session.capabilityReport()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.inspectingAssetID == assetID else { return }
                self.rawCapabilities = report.0
                self.rawNativeTemperature = report.1?.nativeNeutralTemperature
                self.rawNativeTint = report.1?.nativeNeutralTint
                LatencyMetrics.record(
                    "p0.edit.session_prepare_ms",
                    milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000
                )
            }
        }
    }

    private func neighborIDs(around id: UUID, radius: Int) -> [UUID] {
        let items = visibleItems
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return [id] }
        let lo = max(0, idx - radius)
        let hi = min(items.count, idx + radius + 1)
        return Array(items[lo..<hi].map(\.id))
    }

    struct RenderURLs {
        var rawURL: URL?
        var proxyURL: URL?
    }

    func resolveRenderURLs(for assetID: UUID) -> RenderURLs? {
        guard let asset = assets.first(where: { $0.id == assetID }) else { return nil }
        let rawPath = asset.source.originalPath
        let rawExists = FileManager.default.fileExists(atPath: rawPath)
            && asset.source.availability != .missing
        let rawURL = rawExists ? URL(fileURLWithPath: rawPath) : nil
        let proxyPath = asset.proxyPath ?? asset.thumbPath ?? asset.gridThumbPath
        let proxyURL = proxyPath.map { URL(fileURLWithPath: $0) }
        if rawURL == nil && proxyURL == nil { return nil }
        return RenderURLs(rawURL: rawURL, proxyURL: proxyURL)
    }

    // MARK: - Focus / selection

    func setFocus(_ id: UUID?) {
        let start = CFAbsoluteTimeGetCurrent()
        if inspectingAssetID != nil, let id, id != inspectingAssetID {
            flushPendingEditIfNeeded()
        }
        let changed = focusedAssetID != id
        focusedAssetID = id
        if inspectingAssetID != nil, let id {
            let photoChanged = inspectingAssetID != id
            inspectingAssetID = id
            if photoChanged {
                // Debounce settle/prewarm — arrow spam was launching N settled RAW demosaics.
                scheduleInspectionWarm(around: id)
            }
            LatencyMetrics.record(
                "p0.edit.nav_to_neighbor_ms",
                milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000
            )
        }
        if let id, let asset = assets.first(where: { $0.id == id }),
           let path = asset.thumbPath ?? asset.gridThumbPath {
            ThumbCache.shared.prefetch(path)
            LatencyMetrics.record(
                "p0.focus_to_preview",
                milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000
            )
        }
        if inspectingAssetID == nil, let id,
           let chapter = ShootChapterArrangement.chapter(containing: id, in: chapters) {
            activeChapterID = chapter.id
        }
        if changed {
            schedulePersistRestore()
        }
    }

    func selectChapter(_ id: String, focus: ChapterFocusPreference = .firstUndecided) {
        guard let chapter = chapters.first(where: { $0.id == id }) else { return }
        activeChapterID = chapter.id
        switch focus {
        case .last:
            if let last = chapter.bursts.last?.preferredCoverID(in: assets) {
                setFocus(last)
            }
        case .firstUndecided:
            let covers = chapter.bursts.compactMap { $0.preferredCoverID(in: assets) }
            let undecided = covers.first { id in
                assets.first(where: { $0.id == id })?.cull == .undecided
            }
            setFocus(undecided ?? covers.first ?? chapter.assetIDs.first)
        }
        prefetchChapterCovers()
    }

    func reconcileActiveChapter() {
        let list = chapters
        if let focus = focusedAssetID,
           let match = ShootChapterArrangement.chapter(containing: focus, in: list) {
            activeChapterID = match.id
            prefetchChapterCovers()
            return
        }
        if let activeChapterID, list.contains(where: { $0.id == activeChapterID }) {
            prefetchChapterCovers()
            return
        }
        activeChapterID = list.first?.id
        prefetchChapterCovers()
    }

    /// Warm grid-tier covers for this chapter and its neighbors.
    func prefetchChapterCovers() {
        let list = chapters
        guard let current = activeChapter else { return }
        var targets = [current]
        if let index = list.firstIndex(where: { $0.id == current.id }) {
            if list.indices.contains(index + 1) { targets.append(list[index + 1]) }
            if list.indices.contains(index - 1) { targets.append(list[index - 1]) }
        }
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let paths = targets.flatMap(\.bursts).compactMap { burst -> String? in
            guard let coverID = burst.preferredCoverID(in: assets),
                  let asset = byID[coverID] else { return nil }
            return asset.gridThumbPath ?? asset.thumbPath
        }
        ThumbCache.shared.prefetchPaths(paths, maxPixelSize: PhotoImageTier.gridMaxPixelSize, allowRAW: false)
    }

    func moveFocus(dx: Int, dy: Int, columns _: Int) {
        if inspectingAssetID != nil {
            let items = visibleItems
            guard !items.isEmpty else { return }
            let step = dx != 0 ? dx : dy
            guard step != 0 else { return }
            let current = focusedAssetID.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? 0
            let next = min(max(current + step, 0), items.count - 1)
            if items[next].id != focusedAssetID {
                setFocus(items[next].id)
            }
            return
        }

        if walkingKeptRail, dx != 0 {
            walkKeptRail(dx)
            return
        }

        let list = chapters
        guard let chapter = activeChapter else { return }

        if dy != 0 {
            walkingKeptRail = false
            guard let index = list.firstIndex(where: { $0.id == chapter.id }) else { return }
            let next = index + dy
            guard list.indices.contains(next) else { return }
            selectChapter(list[next].id, focus: dy < 0 ? .last : .firstUndecided)
            return
        }

        guard dx != 0 else { return }

        if let leaned = leanedBurst, leaned.frameCount > 1 {
            let covers = leaned.frames.map(\.coverID)
            let current = focusedAssetID.flatMap { id in covers.firstIndex(of: id) } ?? 0
            let next = min(max(current + dx, 0), covers.count - 1)
            setFocus(covers[next])
            return
        }

        let bursts = displayedBursts(in: chapter)
        guard !bursts.isEmpty else { return }
        let currentBurst = bursts.firstIndex { burst in
            focusedAssetID.map { burst.assetIDs.contains($0) } ?? false
        } ?? 0
        let next = min(max(currentBurst + dx, 0), bursts.count - 1)
        if let cover = bursts[next].preferredCoverID(in: assets) {
            setFocus(cover)
        }
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

    /// Toggle selection of the focused/inspected photograph without changing focus.
    func toggleSelectionOfFocused() {
        guard let id = focusedAssetID ?? inspectingAssetID else { return }
        if selectedAssetIDs.contains(id) {
            selectedAssetIDs.remove(id)
        } else {
            selectedAssetIDs.insert(id)
        }
    }

    var focusedIsSelected: Bool {
        guard let id = focusedAssetID ?? inspectingAssetID else { return false }
        return selectedAssetIDs.contains(id)
    }

    var focusedBurst: ShootBurst? {
        guard let focus = focusedAssetID, let chapter = activeChapter else { return nil }
        return chapter.bursts.first { $0.assetIDs.contains(focus) }
    }

    var leanedBurst: ShootBurst? {
        guard let leanedBurstID else { return nil }
        return activeChapter?.bursts.first { $0.id == leanedBurstID }
            ?? chapters.flatMap(\.bursts).first { $0.id == leanedBurstID }
    }

    var keptRailAssets: [AssetRecord] {
        assets.filter { $0.cull == .keep }
    }

    func displayedBursts(in chapter: ShootChapter) -> [ShootBurst] {
        var bursts = chapter.bursts.filter { $0.boardRole(in: assets) != .gone }
        if lookGlancing, !glanceBurstIDs.isEmpty {
            let rank = Dictionary(uniqueKeysWithValues: glanceBurstIDs.enumerated().map { ($0.element, $0.offset) })
            bursts.sort { lhs, rhs in
                (rank[lhs.id] ?? Int.max) < (rank[rhs.id] ?? Int.max)
            }
        }
        return bursts
    }

    func keepFocusedBurst() {
        guard inspectingAssetID == nil else { return }
        guard let chapter = activeChapter, let burst = focusedBurst else { return }
        let orderBefore = shoot?.finalSetOrder.assetIDs ?? []
        let chapterBefore = chapter.id
        let focusBefore = focusedAssetID
        var marks: [ChapterKeepCommand.Mark] = []

        func apply(_ id: UUID, _ after: CullDecision) {
            guard let index = assets.firstIndex(where: { $0.id == id }) else { return }
            let before = assets[index].cull
            guard before != after else { return }
            marks.append(ChapterKeepCommand.Mark(assetID: id, before: before, after: after))
            assets[index].cull = after
            assets[index].userDecidedAt = after == .undecided ? nil : Date()
        }

        for id in burst.assetIDs { apply(id, .keep) }
        for other in chapter.bursts where other.id != burst.id {
            for id in other.assetIDs { apply(id, .reject) }
        }
        guard !marks.isEmpty else { return }

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

        travelingBurstID = burst.id
        undoCoordinator.push(
            ChapterKeepCommand(
                marks: marks,
                finalOrderBefore: orderBefore,
                finalOrderAfter: orderAfter,
                chapterBefore: chapterBefore,
                focusBefore: focusBefore,
                burstID: burst.id
            )
        )
        for mark in marks {
            journalCullCommit(
                CullMutationCommand(
                    assetID: mark.assetID,
                    before: mark.before,
                    after: mark.after,
                    finalOrderBefore: orderBefore,
                    finalOrderAfter: orderAfter
                )
            )
        }
        persistShootImmediately()
        advanceIfChapterEmpty(from: chapterBefore)
    }

    private func applyChapterKeepUndo(_ command: ChapterKeepCommand) {
        for mark in command.marks {
            guard let index = assets.firstIndex(where: { $0.id == mark.assetID }) else { continue }
            assets[index].cull = mark.before
            assets[index].userDecidedAt = mark.before == .undecided ? nil : Date()
        }
        if var shoot {
            shoot.finalSetOrder.assetIDs = command.finalOrderBefore
            shoot.assets = assets
            self.shoot = shoot
        }
        travelingBurstID = nil
        walkingKeptRail = false
        if let chapterID = command.chapterBefore {
            selectChapter(chapterID, focus: .firstUndecided)
        }
        if let focus = command.focusBefore {
            setFocus(focus)
        }
        persistShootImmediately()
    }

    private func advanceIfChapterEmpty(from chapterID: String) {
        let list = chapters
        guard let chapter = list.first(where: { $0.id == chapterID }) else { return }
        let hasWork = chapter.bursts.contains { $0.boardRole(in: assets) == .plate }
        guard !hasWork else { return }
        if let next = list.drop(while: { $0.id != chapterID }).dropFirst().first(where: { candidate in
            candidate.bursts.contains { $0.boardRole(in: assets) == .plate }
        }) {
            selectChapter(next.id)
        }
    }

    func activateFocusedPhotograph() {
        guard inspectingAssetID == nil else { return }
        guard let burst = focusedBurst else {
            openFocusedPhotograph()
            return
        }
        if leanedBurstID == burst.id || burst.frameCount <= 1 {
            openFocusedPhotograph()
        } else {
            leanIntoBurst(burst.id)
        }
    }

    func leanIntoBurst(_ id: String) {
        leanedBurstID = id
        if let burst = chapters.flatMap(\.bursts).first(where: { $0.id == id }) {
            let covers = burst.frames.map(\.coverID)
            let undecided = covers.first { cover in
                assets.first(where: { $0.id == cover })?.cull == .undecided
            }
            setFocus(undecided ?? covers.first ?? burst.coverID)
        }
    }

    func leaveBurstLean() {
        leanedBurstID = nil
    }

    func beginLookGlance() {
        guard inspectingAssetID == nil, let chapter = activeChapter else { return }
        lookGlancing = true
        glanceBurstIDs = ChapterLookGlance.orderedIDs(
            bursts: chapter.bursts.filter { $0.boardRole(in: assets) != .gone },
            assets: assets,
            focusedBurstID: focusedBurst?.id
        )
    }

    func endLookGlance() {
        lookGlancing = false
        glanceBurstIDs = []
    }

    func setHoldingLoupe(_ holding: Bool) {
        holdingLoupe = holding
    }

    func setHoldingClipping(_ holding: Bool) {
        holdingClipping = holding
    }

    func toggleKeptRailWalk() {
        if walkingKeptRail {
            walkingKeptRail = false
            return
        }
        guard !keptRailAssets.isEmpty else { return }
        walkingKeptRail = true
        if let first = keptRailAssets.first {
            focusedAssetID = first.id
        }
    }

    func focusKeptAsset(_ id: UUID) {
        walkingKeptRail = true
        setFocus(id)
    }

    private func walkKeptRail(_ dx: Int) {
        let kept = keptRailAssets
        guard !kept.isEmpty else {
            walkingKeptRail = false
            return
        }
        let current = focusedAssetID.flatMap { id in kept.firstIndex(where: { $0.id == id }) } ?? 0
        let next = min(max(current + dx, 0), kept.count - 1)
        focusedAssetID = kept[next].id
    }

    func openFocusedPhotograph() {
        guard let id = focusedAssetID ?? selectedAssetIDs.first else { return }
        schedulePersistRestore()
        leanedBurstID = nil
        walkingKeptRail = false
        lookGlancing = false
        inspectingAssetID = id
        focusedAssetID = id
        expandedAdjustmentSection = .light
        prewarmInspection(around: id)
        persistRestoreNow()
    }

    func closeInspection() {
        flushPendingEditIfNeeded()
        showingBefore = false
        pendingScrollRestore = true
        inspectingAssetID = nil
        persistRestoreNow()
    }

    /// Contact sheet → grouping. Keeps shoot, cull marks, and selection; Esc returns to the grid.
    func enterGrouping() {
        guard shoot != nil else { return }
        flushPendingEditIfNeeded()
        showingBefore = false
        inspectingAssetID = nil
        route = .grouping
        persistRestoreNow()
    }

    func leaveGrouping() {
        guard route == .grouping else { return }
        route = .contactSheet
        pendingScrollRestore = true
        persistRestoreNow()
    }

    /// Pixel zoom request for the inspecting photograph (double-click / 1:1).
    func requestOneToOneZoom(for assetID: UUID) {
        guard let urls = resolveRenderURLs(for: assetID), let raw = urls.rawURL else { return }
        let recipe = recipe(for: assetID)
        let region = DevelopRenderRegion(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        Task {
            await developScheduler.renderOneToOne(
                photoID: assetID,
                rawURL: raw,
                proxyURL: urls.proxyURL,
                recipe: recipe,
                region: region
            )
        }
    }

    func adjustDensity(_ delta: Int) {
        densityLeaned = true
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
        flushPendingEditIfNeeded()
        preparationTask?.cancel()
        capabilityTask?.cancel()
        prewarmTask?.cancel()
        persistRestoreNow()
        releaseFolderAccess()
        releaseDevelopScheduler()
        shoot = nil
        assets = []
        status = ContactSheetPreparationStatus()
        focusedAssetID = nil
        activeChapterID = nil
        selectedAssetIDs = []
        inspectingAssetID = nil
        densityLeaned = false
        holdingLoupe = false
        holdingClipping = false
        lookGlancing = false
        glanceBurstIDs = []
        leanedBurstID = nil
        walkingKeptRail = false
        travelingBurstID = nil
        showingBefore = false
        clearGestureState()
        undoCoordinator.clear()
        sidecarManagedHashes = [:]
        sidecarDriftAssetIDs = []
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
            reconcileActiveChapter()
            route = .contactSheet
        case .assetsReplaced(let assets, let status):
            let focus = focusedAssetID
            let selection = selectedAssetIDs
            self.assets = assets
            self.shoot?.assets = assets
            self.status = status
            focusedAssetID = focus.flatMap { id in assets.contains(where: { $0.id == id }) ? id : nil } ?? focus
            selectedAssetIDs = selection.intersection(Set(assets.map(\.id)))
            reconcileActiveChapter()
        case .assetsInserted(let assets, let status):
            mergeAssets(assets)
            self.status = status
            reconcileActiveChapter()
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
            reconcileActiveChapter()
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
        prefetchChapterCovers()
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
        prefetchChapterCovers()
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
            prewarmInspection(around: focusedAssetID)
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

    /// Cull mutations coalesce disk writes so P/X spam stays responsive.
    private func schedulePersistShoot() {
        shootPersistTask?.cancel()
        shootPersistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.persistShootImmediately() }
        }
    }

    /// Cull mutations persist immediately — not wait for restore debounce.
    private func persistShootImmediately() {
        shootPersistTask?.cancel()
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

    // MARK: - CP2 decision journal (append-only beside shoot — D35 / D13)

    private func journalRawFolderURL() -> URL? {
        guard let path = shoot?.rawFolder?.originalPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Committed cull only — staging and undo paths never reach the journal (D13).
    private func journalCullCommit(_ command: CullMutationCommand) {
        guard let folder = journalRawFolderURL() else { return }
        try? ShootDecisionJournal.appendCullCommit(command, besideShootFolder: folder)
    }

    /// Committed edit only — gesture staging is not journaled until commit (D13).
    private func journalEditCommit(_ command: EditMutationCommand) {
        guard let folder = journalRawFolderURL() else { return }
        try? ShootDecisionJournal.appendEditCommit(command, besideShootFolder: folder)
    }

    /// Open XMP beside the original — durable interoperable form (D36).
    private func sidecarEditCommit(_ command: EditMutationCommand) {
        guard let rawURL = resolveRenderURLs(for: command.assetID)?.rawURL else { return }
        guard let result = try? ShootSidecarStore.writeCommittedEdit(command.after, besideOriginal: rawURL) else {
            return
        }
        sidecarManagedHashes[command.assetID] = result.managedFieldsHash
        sidecarDriftAssetIDs.remove(command.assetID)
    }

    /// Journal + in-memory recipe win when sidecar changes underneath a running session.
    func reconcileSidecarDrift(for assetID: UUID) -> SidecarReconciliation? {
        guard let rawURL = resolveRenderURLs(for: assetID)?.rawURL else { return nil }
        let xmpURL = ShootSidecarStore.sidecarURL(besideOriginal: rawURL)
        let sessionRecipe = recipe(for: assetID)
        guard let outcome = try? ShootSidecarStore.reconcileDuringSession(
            sessionRecipe: sessionRecipe,
            lastWrittenHash: sidecarManagedHashes[assetID],
            xmpURL: xmpURL
        ) else { return nil }
        if case .externalDrift = outcome {
            sidecarDriftAssetIDs.insert(assetID)
        }
        return outcome
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
