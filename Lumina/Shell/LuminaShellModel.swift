import AppKit
import Observation
import SwiftUI

enum LuminaRoute: Equatable, Hashable {
    case home
    case shootSelection
    case workspace
    case finish
}

/// Owns route, lens, selection identity, and cached presentation snapshots.
/// Adapters run only when the project fingerprint changes — never on every body evaluation.
@MainActor
@Observable
final class LuminaShellModel {
    var route: LuminaRoute = .home
    var lens: WorkspaceLens = .attempts
    var workspaceStage: WorkspaceStage = .workbench
    var isRowExpanded = true
    var treatmentPreviewMode: TreatmentPreviewMode = .current
    var showDetailedEdits = false
    var rowPreviewActive = false
    var workbenchScrollAnchor: String?
    var canvasScrollAnchor: String?
    var proofScrollAnchor: String?
    var selectedAssetID: AssetID?
    var selectedGroupID: String?
    var scrollTargetGroupID: String?
    var isFocusMode = false
    var showInspector = false
    var showShortcuts = false
    var pendingPeerSuggestion: PeerCullSuggestion?
    var developOffsets: DevelopAdjustments = .zero
    var stackPreviewMix: Double = 1
    var workspaceRevealToken: Int = 0
    /// One-step Undo for Workbench routing decisions.
    var decisionUndo: DecisionUndoRecord?
    /// Transient non-modal receipt — does not resize the workspace.
    var decisionReceipt: DecisionReceipt?
    /// Last round receipt for ⌘Z after the banner auto-dismisses.
    var lastRoundReceipt: RoundReceipt?
    /// Darkroom gathering + two-beat commit model.
    var workbenchSelection = WorkbenchSelection()
    /// Active staged copy snapshot — banner/header/receipt share `scopeCount` (A1).
    var stagingCopySnapshot: StagingCopySnapshot?
    /// Fast-run travel shortening.
    var fastRunTracker = LuminaTokens.FastRunTracker()
    /// Treatment stage (Edit) open over the workbench.
    var isTreatmentStageOpen = false
    /// Story Read mode — chrome dropped, Esc restores scroll.
    var isReadMode = false
    /// Preserved story pane fraction across Edit sessions.
    var preservedStoryFraction: Double?
    /// Asset currently flying toward the emerging set (matched-geometry bridge).
    var routingFlightID: AssetID?
    /// Grouped flight proxy for a multi-photo Advance stack.
    var routingFlightIDs: [AssetID] = []
    /// Latched crop inside focused edit — Esc dismisses, ⏎ applies (hi-fi frame C).
    var cropSession: CropSession?
    private let developProposalEngine: DevelopProposalEngine = HistogramDevelopProposalEngine()
    private var previewAnimationTask: Task<Void, Never>?
    private var developPersistTask: Task<Void, Never>?
    private var receiptDismissTask: Task<Void, Never>?
    private var flightClearTask: Task<Void, Never>?

    struct DecisionUndoRecord: Equatable {
        let photoID: AssetID
        let priorTier: PhotoTier
        let priorFlagged: Bool
        let priorUncertaintyKind: UncertaintyKind
        let priorWhyUncertain: String?
        let applied: AssetDecision
        let receiptLabel: String
    }

    struct DecisionReceipt: Equatable {
        let id: UUID
        let message: String
        let roundID: UUID?

        init(id: UUID = UUID(), message: String, roundID: UUID? = nil) {
            self.id = id
            self.message = message
            self.roundID = roundID
        }
    }

    var fixtureHome: HomePresentation?
    var fixtureShoots: ShootSelectionPresentation?
    var fixtureWorkspace: WorkspacePresentation?
    var fixtureFinish: FinishPresentation?

    // Cached adapter outputs keyed by project fingerprint + lens.
    private var cachedFingerprint = ""
    private var cachedHome: HomePresentation?
    private var cachedShoots: ShootSelectionPresentation?
    private var cachedAttempts: WorkspacePresentation?
    private var cachedLight: WorkspacePresentation?
    private var cachedFinish: FinishPresentation?

    func openHome() {
        dismissCrop(revert: true)
        route = .home
        isFocusMode = false
        showInspector = false
    }

    func openShootSelection() {
        route = .shootSelection
        isFocusMode = false
        showInspector = false
    }

    func openWorkspace(lens: WorkspaceLens = .attempts) {
        self.lens = lens
        route = .workspace
        workspaceStage = .workbench
        isFocusMode = false
        showInspector = false
        workspaceRevealToken &+= 1
    }

    func setWorkspaceStage(_ stage: WorkspaceStage) {
        guard stage != workspaceStage else { return }
        dismissCrop(revert: true)
        if workspaceStage == .workbench {
            workbenchScrollAnchor = selectedGroupID
        } else if workspaceStage == .canvas {
            canvasScrollAnchor = selectedAssetID?.uuidString
        } else if workspaceStage == .proof {
            proofScrollAnchor = canvasScrollAnchor
        }
        workspaceStage = stage
    }

    func toggleRowExpanded() {
        isRowExpanded.toggle()
    }

    func previewAutoTreatment(model: ProjectViewModel) {
        treatmentPreviewMode = .auto
        rowPreviewActive = true
        replayStackPreview()
    }

    func toggleDetailedEdits() {
        showDetailedEdits.toggle()
    }

    func toggleRowPreview() {
        rowPreviewActive.toggle()
        if rowPreviewActive { replayStackPreview() }
        else { stackPreviewMix = 1 }
    }

    /// Effective develop offsets for rendering given preview mode.
    func effectiveDevelopOffsets(model: ProjectViewModel, for photoID: AssetID?) -> DevelopAdjustments {
        switch treatmentPreviewMode {
        case .original:
            return .zero
        case .auto, .current:
            return developOffsets
        }
    }

    /// Base recipe for rendering given preview mode.
    func effectiveBaseRecipe(model: ProjectViewModel, for photoID: AssetID?) -> DevelopRecipe {
        guard let photoID, let photo = model.photo(with: photoID) else { return .neutral }
        switch treatmentPreviewMode {
        case .original:
            return .neutral
        case .auto, .current:
            return model.appliedRecipe(for: photo)
        }
    }

    func openFinish() {
        route = .finish
        isFocusMode = false
        showInspector = false
    }

    func selectAsset(_ id: AssetID) {
        selectedAssetID = id
    }

    func selectGroup(_ id: String) {
        selectedGroupID = id
    }

    func setLens(_ newLens: WorkspaceLens) {
        guard newLens != lens else { return }
        lens = newLens
    }

    func toggleFocus() {
        isFocusMode.toggle()
        if isFocusMode { showInspector = false }
    }

    func toggleInspector() {
        showInspector.toggle()
    }

    /// Escape closes transient overlays — never dumps the workspace to Home.
    func handleEscape(model: ProjectViewModel? = nil) -> Bool {
        if dismissCrop(revert: true) {
            return true
        }
        if workbenchSelection.staged != nil {
            let wasDevelop = workbenchSelection.staged?.isDevelopStaging == true
            workbenchSelection.cancel()
            stagingCopySnapshot = nil
            if wasDevelop, let model, let photoID = selectedAssetID ?? model.cursor {
                loadDevelop(for: photoID, model: model)
            }
            LuminaHaptics.alignment()
            return true
        }
        if isTreatmentStageOpen {
            dismissCrop(revert: true)
            isTreatmentStageOpen = false
            return true
        }
        if isReadMode {
            isReadMode = false
            return true
        }
        if isFocusMode {
            isFocusMode = false
            return true
        }
        if workspaceStage == .proof {
            setWorkspaceStage(.canvas)
            return true
        }
        if workspaceStage == .canvas {
            setWorkspaceStage(.workbench)
            return true
        }
        if showDetailedEdits {
            showDetailedEdits = false
            return true
        }
        if rowPreviewActive {
            rowPreviewActive = false
            stackPreviewMix = 1
            return true
        }
        if showInspector {
            showInspector = false
            return true
        }
        if showShortcuts {
            showShortcuts = false
            return true
        }
        if !workbenchSelection.isEmpty {
            workbenchSelection.clearSelection()
            return true
        }
        return false
    }

    // MARK: - Snapshot access (cached)

    func refreshSnapshotsIfNeeded(model: ProjectViewModel) {
        let fingerprint = PresentationAdapter.projectFingerprint(model)
        guard fingerprint != cachedFingerprint else { return }
        cachedFingerprint = fingerprint
        cachedHome = PresentationAdapter.home(from: model)
        cachedShoots = PresentationAdapter.shootSelection(from: model)
        cachedAttempts = PresentationAdapter.workspace(from: model, lens: .attempts, selectedAssetID: selectedAssetID ?? model.cursor)
        cachedLight = PresentationAdapter.workspace(from: model, lens: .light, selectedAssetID: selectedAssetID ?? model.cursor)
        cachedFinish = PresentationAdapter.finish(from: model)

        // Warm the browse spine once when project photos change — not on selection.
        if let photos = model.project?.photos, !photos.isEmpty {
            PreviewSpine.shared.warm(photos: photos, focus: selectedAssetID ?? model.cursor)
        }
    }

    func homePresentation(model: ProjectViewModel) -> HomePresentation {
        if let fixtureHome { return fixtureHome }
        refreshSnapshotsIfNeeded(model: model)
        return cachedHome ?? PresentationAdapter.home(from: model)
    }

    func shootPresentation(model: ProjectViewModel) -> ShootSelectionPresentation {
        if let fixtureShoots { return fixtureShoots }
        refreshSnapshotsIfNeeded(model: model)
        return cachedShoots ?? PresentationAdapter.shootSelection(from: model)
    }

    func workspacePresentation(model: ProjectViewModel) -> WorkspacePresentation {
        if let fixtureWorkspace {
            let groups = fixtureWorkspace.lens == lens
                ? fixtureWorkspace.groups
                : (lens == .light
                   ? PresentationFixtures.lightWorkspace().groups
                   : PresentationFixtures.attemptWorkspace().groups)
            return WorkspacePresentation(
                shootTitle: fixtureWorkspace.shootTitle,
                lens: lens,
                groups: groups,
                selectedAssetID: selectedAssetID ?? fixtureWorkspace.selectedAssetID,
                selectedGroupID: selectedGroupID ?? fixtureWorkspace.selectedGroupID,
                progressCurrent: fixtureWorkspace.progressCurrent,
                progressTotal: fixtureWorkspace.progressTotal,
                inspectorAvailable: fixtureWorkspace.inspectorAvailable
            )
        }

        refreshSnapshotsIfNeeded(model: model)
        let base = (lens == .light ? cachedLight : cachedAttempts)
            ?? PresentationAdapter.workspace(from: model, lens: lens, selectedAssetID: selectedAssetID ?? model.cursor)

        // Selection / group overlay only — do not rebuild groups.
        return base.overlaying(
            lens: lens,
            selectedAssetID: selectedAssetID ?? base.selectedAssetID,
            selectedGroupID: selectedGroupID ?? base.selectedGroupID
        )
    }

    func finishPresentation(model: ProjectViewModel) -> FinishPresentation {
        if let fixtureFinish { return fixtureFinish }
        refreshSnapshotsIfNeeded(model: model)
        return cachedFinish ?? PresentationAdapter.finish(from: model)
    }

    func invalidateCache() {
        cachedFingerprint = ""
    }

    func resetStackPreview() {
        previewAnimationTask?.cancel()
        developOffsets = .zero
        stackPreviewMix = 1
    }

    func loadDevelop(for photoID: AssetID, model: ProjectViewModel) {
        developPersistTask?.cancel()
        developOffsets = model.developOffsets(for: photoID)
        stackPreviewMix = 1
    }

    func setDevelopOffsets(_ offsets: DevelopAdjustments, for photoID: AssetID, model: ProjectViewModel) {
        developOffsets = offsets
        developPersistTask?.cancel()
        developPersistTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            model.persistDevelopOffsets(offsets, for: photoID)
        }
    }

    func syncSelectionFromModel(_ model: ProjectViewModel) {
        if selectedAssetID == nil {
            selectedAssetID = model.cursor
        }
        if let id = selectedAssetID ?? model.cursor {
            loadDevelop(for: id, model: model)
        }
    }

    func adjustStackExposure(delta: Double, model: ProjectViewModel) {
        var next = developOffsets
        next.exposure = min(max(next.exposure + delta, -3), 3)
        guard let id = selectedAssetID else {
            developOffsets = next
            animateStackPreview(fromZero: true)
            return
        }
        setDevelopOffsets(next, for: id, model: model)
        animateStackPreview(fromZero: true)
    }

    func replayStackPreview() {
        animateStackPreview(fromZero: true)
    }

    private func animateStackPreview(fromZero: Bool = false) {
        previewAnimationTask?.cancel()
        if fromZero { stackPreviewMix = 0 }
        previewAnimationTask = Task {
            let steps = 18
            let duration = 0.55
            let stepSleep = duration / Double(steps)
            if fromZero { stackPreviewMix = 0 }
            for i in 1...steps {
                if Task.isCancelled { return }
                let t = Double(i) / Double(steps)
                let eased = 1 - pow(1 - t, 2.2)
                stackPreviewMix = eased
                try? await Task.sleep(nanoseconds: UInt64(stepSleep * 1_000_000_000))
            }
            stackPreviewMix = 1
        }
    }

    func applyDecision(_ decision: AssetDecision, for assetID: AssetID? = nil, model: ProjectViewModel) {
        guard model.project != nil else { return }
        let targetID = assetID ?? selectedAssetID ?? model.cursor
        guard let targetID else { return }
        guard let snapshot = model.photoRoutingSnapshot(for: targetID) else { return }
        model.setCursor(targetID)

        pendingPeerSuggestion = nil

        let receiptLabel: String
        switch decision {
        case .cut:
            model.setTier(.reject, for: targetID)
            receiptLabel = "Set aside"
            routingFlightID = nil
        case .keep:
            model.setTier(.keep, for: targetID)
            receiptLabel = "Added to set"
            beginRoutingFlight(targetID)
        case .needsMe:
            if snapshot.isFlagged && snapshot.tier == .unranked {
                // Second Hold clears the marker.
                model.clearRoutingDecision(for: targetID)
                decisionUndo = nil
                showReceipt("Hold cleared")
                invalidateCache()
                refreshSnapshotsIfNeeded(model: model)
                return
            }
            model.setHold(for: targetID)
            receiptLabel = "Hold"
            routingFlightID = nil
        case .undecided, .anchor:
            return
        }

        decisionUndo = DecisionUndoRecord(
            photoID: targetID,
            priorTier: snapshot.tier,
            priorFlagged: snapshot.isFlagged,
            priorUncertaintyKind: snapshot.uncertaintyKind,
            priorWhyUncertain: snapshot.whyUncertain,
            applied: decision,
            receiptLabel: receiptLabel
        )
        showReceipt(receiptLabel)

        withAnimation(LuminaTokens.Motion.photo) {
            invalidateCache()
            refreshSnapshotsIfNeeded(model: model)
        }
        let presentation = workspacePresentation(model: model)
        advanceWithinGroup(afterDeciding: targetID, presentation: presentation, model: model)
    }

    func undoLastDecision(model: ProjectViewModel) {
        if let round = lastRoundReceipt {
            undoRound(round, model: model)
            return
        }
        guard let record = decisionUndo else { return }
        model.restorePhotoState(
            photoID: record.photoID,
            tier: record.priorTier,
            isFlagged: record.priorFlagged,
            uncertaintyKind: record.priorUncertaintyKind,
            whyUncertain: record.priorWhyUncertain
        )
        decisionUndo = nil
        routingFlightID = nil
        routingFlightIDs = []
        selectedAssetID = record.photoID
        model.setCursor(record.photoID)
        showReceipt("Undone")
        invalidateCache()
        refreshSnapshotsIfNeeded(model: model)
        loadDevelop(for: record.photoID, model: model)
        _ = PreviewSpine.shared.paint(id: record.photoID, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
    }

    /// Apply the leader's current treatment (base recipe + live offsets) to every
    /// photo in the leader's set. Heal spots stay on the leader only — they are
    /// pixel positions and do not transfer. Returns the number of photos treated.
    @discardableResult
    func applyTreatmentToSet(model: ProjectViewModel, presentation: WorkspacePresentation) -> Int {
        guard let leaderID = workbenchSelection.leader ?? selectedAssetID,
              let leaderPhoto = model.photo(with: leaderID) else { return 0 }
        let recipe = model.appliedRecipe(for: leaderPhoto).applying(developOffsets)
        guard let group = presentation.groups.first(where: { g in
            g.assets.contains { $0.id == leaderID }
        }), group.assets.count > 1 else { return 0 }

        var applied = 0
        for asset in group.assets {
            var target = recipe
            if asset.id != leaderID {
                target.retouch = model.photo(with: asset.id)?.recipe?.retouch ?? []
            }
            model.persistRecipe(target, for: asset.id)
            applied += 1
        }
        showReceipt("Treatment applied to \(applied) in set")
        return applied
    }

    // MARK: - Round commit (one receipt = one undo)

    /// Commits the staged action across the gathered selection as one ledger transaction.
    /// Empty selection / missing stage are no-ops at the model level.
    @discardableResult
    func commitRound(_ selection: WorkbenchSelection, model: ProjectViewModel) -> RoundReceipt? {
        guard let action = selection.staged, !selection.ids.isEmpty else { return nil }
        let targets = selection.ids
        let priorEmerging = model.emergingSetPresentations().map(\.id)

        var entries: [DecisionLedgerEntry] = []
        var advanceCount = 0
        var setAsideCount = 0
        var holdCount = 0
        var treatCount = 0
        var developCount = 0

        switch action {
        case .advance:
            for id in targets {
                guard let snapshot = model.photoRoutingSnapshot(for: id) else { continue }
                entries.append(DecisionLedgerEntry(
                    photoID: id,
                    priorTier: snapshot.tier,
                    priorFlagged: snapshot.isFlagged,
                    priorUncertaintyKind: snapshot.uncertaintyKind,
                    priorWhyUncertain: snapshot.whyUncertain,
                    applied: .keep
                ))
                model.setTier(.keep, for: id, userInitiated: true)
                advanceCount += 1
            }
            beginRoutingFlightStack(targets)

        case .setAside:
            for id in targets {
                guard let snapshot = model.photoRoutingSnapshot(for: id) else { continue }
                entries.append(DecisionLedgerEntry(
                    photoID: id,
                    priorTier: snapshot.tier,
                    priorFlagged: snapshot.isFlagged,
                    priorUncertaintyKind: snapshot.uncertaintyKind,
                    priorWhyUncertain: snapshot.whyUncertain,
                    applied: .cut
                ))
                model.setTier(.reject, for: id, userInitiated: true)
                setAsideCount += 1
            }
            routingFlightID = nil
            routingFlightIDs = []

        case .hold:
            for id in targets {
                guard let snapshot = model.photoRoutingSnapshot(for: id) else { continue }
                entries.append(DecisionLedgerEntry(
                    photoID: id,
                    priorTier: snapshot.tier,
                    priorFlagged: snapshot.isFlagged,
                    priorUncertaintyKind: snapshot.uncertaintyKind,
                    priorWhyUncertain: snapshot.whyUncertain,
                    applied: .needsMe
                ))
                model.setHold(for: id)
                holdCount += 1
            }
            routingFlightID = nil
            routingFlightIDs = []

        case .treat(let recipe):
            let referenceID = selection.leader ?? targets.first
            let referenceFrame = CopyContractBuilder.referenceFrameNumber(
                from: referenceID.flatMap { model.photo(with: $0)?.filename }
            )
            for id in targets {
                guard let snapshot = model.photoRoutingSnapshot(for: id) else { continue }
                let priorRecipe = model.photo(with: id)?.recipe
                entries.append(DecisionLedgerEntry(
                    photoID: id,
                    priorTier: snapshot.tier,
                    priorFlagged: snapshot.isFlagged,
                    priorUncertaintyKind: snapshot.uncertaintyKind,
                    priorWhyUncertain: snapshot.whyUncertain,
                    applied: .undecided,
                    priorRecipe: priorRecipe,
                    appliedRecipe: recipe
                ))
                model.persistRecipe(recipe, for: id)
                treatCount += 1
            }
            if treatCount > 0, let referenceID {
                model.persistAdaptProvenance(
                    referenceFrame: referenceFrame,
                    scopeCount: treatCount,
                    referencePhotoID: referenceID,
                    photoIDs: targets
                )
            }

        case .develop(let proposals):
            for id in targets {
                guard let proposal = proposals[id],
                      let snapshot = model.photoRoutingSnapshot(for: id),
                      let photo = model.photo(with: id) else { continue }
                let priorEdit = photo.effectiveEditRecipe
                entries.append(DecisionLedgerEntry(
                    photoID: id,
                    priorTier: snapshot.tier,
                    priorFlagged: snapshot.isFlagged,
                    priorUncertaintyKind: snapshot.uncertaintyKind,
                    priorWhyUncertain: snapshot.whyUncertain,
                    applied: .undecided,
                    priorRecipe: model.appliedRecipe(for: photo),
                    priorEditRecipe: priorEdit
                ))
                model.persistEditRecipe(proposal, for: id)
                developCount += 1
            }
        }

        guard !entries.isEmpty else { return nil }

        appendRoundLedger(entries: entries, model: model)

        var parts: [String] = []
        if advanceCount > 0 { parts.append("Advanced \(advanceCount)") }
        if setAsideCount > 0 { parts.append("Set aside \(setAsideCount)") }
        if holdCount > 0 { parts.append("Hold \(holdCount)") }
        if treatCount > 0 { parts.append(CopyContract.adaptedReceipt(count: treatCount)) }
        if developCount > 0 { parts.append("Developed → \(developCount) · ⌘Z") }
        let text = parts.isEmpty ? "Round committed" : parts.joined(separator: " · ")

        let receipt = RoundReceipt(
            id: UUID(),
            text: text,
            entries: entries,
            priorEmergingOrder: priorEmerging
        )
        lastRoundReceipt = receipt
        decisionUndo = nil
        selection.markRoundCompleted()
        stagingCopySnapshot = nil
        fastRunTracker.noteConfirm()
        LuminaHaptics.levelChange()
        showRoundReceipt(receipt)

        withAnimation(LuminaTokens.Motion.photo) {
            invalidateCache()
            refreshSnapshotsIfNeeded(model: model)
        }

        if let last = targets.last {
            let presentation = workspacePresentation(model: model)
            advanceWithinGroup(afterDeciding: last, presentation: presentation, model: model)
        }
        return receipt
    }

    func undoRound(_ receipt: RoundReceipt, model: ProjectViewModel) {
        for entry in receipt.entries.reversed() {
            model.restorePhotoState(
                photoID: entry.photoID,
                tier: entry.priorTier,
                isFlagged: entry.priorFlagged,
                uncertaintyKind: entry.priorUncertaintyKind,
                whyUncertain: entry.priorWhyUncertain
            )
            if let priorEdit = entry.priorEditRecipe {
                model.persistEditRecipe(priorEdit, for: entry.photoID)
            } else if let priorRecipe = entry.priorRecipe {
                model.persistRecipe(priorRecipe, for: entry.photoID)
            } else if entry.appliedRecipe != nil {
                model.clearRecipe(for: entry.photoID)
            }
        }
        if lastRoundReceipt?.id == receipt.id {
            lastRoundReceipt = nil
        }
        routingFlightID = nil
        routingFlightIDs = []
        decisionUndo = nil
        if let first = receipt.entries.first {
            selectedAssetID = first.photoID
            model.setCursor(first.photoID)
            loadDevelop(for: first.photoID, model: model)
        }
        showReceipt("Undone")
        invalidateCache()
        refreshSnapshotsIfNeeded(model: model)
    }

    private func appendRoundLedger(entries: [DecisionLedgerEntry], model: ProjectViewModel) {
        guard var project = model.project else { return }
        let tiers = Dictionary(uniqueKeysWithValues: entries.map { ($0.photoID, tier(for: $0.applied)) })
        project.decisionLedger.append(DecisionEvent(
            kind: .round,
            reason: .cullBorderline,
            photoIDs: entries.map(\.photoID),
            proposedTiers: tiers,
            confidenceByPhoto: Dictionary(uniqueKeysWithValues: entries.map { ($0.photoID, 1.0) })
        ))
        model.replaceProject(project)
    }

    private func tier(for decision: AssetDecision) -> PhotoTier {
        switch decision {
        case .keep, .anchor: return .keep
        case .cut: return .reject
        case .needsMe, .undecided: return .unranked
        }
    }

    private func showRoundReceipt(_ receipt: RoundReceipt) {
        let banner = DecisionReceipt(id: UUID(), message: receipt.text, roundID: receipt.id)
        decisionReceipt = banner
        receiptDismissTask?.cancel()
        receiptDismissTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            if decisionReceipt?.id == banner.id {
                decisionReceipt = nil
            }
        }
    }

    private func beginRoutingFlightStack(_ ids: [AssetID]) {
        routingFlightIDs = ids
        routingFlightID = ids.last
        flightClearTask?.cancel()
        flightClearTask = Task {
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            routingFlightID = nil
            routingFlightIDs = []
        }
    }

    func openTreatmentStage() {
        isTreatmentStageOpen = true
        isFocusMode = false
    }

    func closeTreatmentStage() {
        dismissCrop(revert: true)
        isTreatmentStageOpen = false
    }

    func enterReadMode() {
        guard workspaceStage == .canvas || workspaceStage == .proof else {
            setWorkspaceStage(.canvas)
            isReadMode = true
            return
        }
        if workspaceStage == .proof {
            // Already in legacy proof — treat as read.
            isReadMode = true
            return
        }
        isReadMode = true
    }

    func restoreFromFold(assetID: AssetID, model: ProjectViewModel) {
        guard let snapshot = model.photoRoutingSnapshot(for: assetID) else { return }
        decisionUndo = DecisionUndoRecord(
            photoID: assetID,
            priorTier: snapshot.tier,
            priorFlagged: snapshot.isFlagged,
            priorUncertaintyKind: snapshot.uncertaintyKind,
            priorWhyUncertain: snapshot.whyUncertain,
            applied: .undecided,
            receiptLabel: "Restored"
        )
        model.clearRoutingDecision(for: assetID)
        selectedAssetID = assetID
        model.setCursor(assetID)
        showReceipt("Restored")
        invalidateCache()
        refreshSnapshotsIfNeeded(model: model)
        loadDevelop(for: assetID, model: model)
    }

    private func showReceipt(_ message: String) {
        let receipt = DecisionReceipt(id: UUID(), message: message)
        decisionReceipt = receipt
        receiptDismissTask?.cancel()
        receiptDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            if decisionReceipt?.id == receipt.id {
                decisionReceipt = nil
            }
        }
    }

    private func beginRoutingFlight(_ id: AssetID) {
        routingFlightID = id
        routingFlightIDs = [id]
        flightClearTask?.cancel()
        flightClearTask = Task {
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            if routingFlightID == id {
                routingFlightID = nil
                routingFlightIDs = []
            }
        }
    }

    func applyPeerSuggestion(model: ProjectViewModel) {
        guard let suggestion = pendingPeerSuggestion else { return }
        let ids = suggestion.peerAssets.map(\.id)
        model.applyTier(.reject, to: ids)
        pendingPeerSuggestion = nil
        invalidateCache()
        refreshSnapshotsIfNeeded(model: model)
    }

    func applyDecisionToRest(in groupID: String, model: ProjectViewModel, presentation: WorkspacePresentation) {
        guard let group = presentation.groups.first(where: { $0.id == groupID }),
              let leadID = group.leadAsset?.id ?? group.representativeID,
              let lead = group.assets.first(where: { $0.id == leadID }) else { return }

        pendingPeerSuggestion = nil

        switch lead.decision {
        case .keep:
            let peers = model.peerCutSuggestion(afterKeeping: leadID)
            guard !peers.isEmpty else { return }
            model.applyTier(.reject, to: peers.map(\.id))
        case .cut:
            let undecided = group.assets
                .filter { $0.id != leadID && $0.decision == .undecided }
                .map(\.id)
            guard !undecided.isEmpty else { return }
            model.applyTier(.reject, to: undecided)
        case .needsMe, .undecided, .anchor:
            return
        }

        invalidateCache()
        refreshSnapshotsIfNeeded(model: model)
    }

    func selectLead(in groupID: String, model: ProjectViewModel, presentation: WorkspacePresentation) {
        guard let group = presentation.groups.first(where: { $0.id == groupID }) else { return }
        selectedGroupID = groupID
        scrollTargetGroupID = groupID
        let leadID = group.captureOrderedAssets
            .first(where: { $0.decision == .undecided })?.id
            ?? group.captureOrderedAssets.first?.id
        guard let leadID else { return }
        selectedAssetID = leadID
        if model.project != nil { model.setCursor(leadID) }
        loadDevelop(for: leadID, model: model)
        _ = PreviewSpine.shared.paint(id: leadID, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
    }

    private func refreshPeerSuggestion(after decision: AssetDecision, for photoID: AssetID, model: ProjectViewModel) {
        let peers: [PhotoRecord]
        switch decision {
        case .keep:
            peers = model.peerCutSuggestion(afterKeeping: photoID)
        case .cut:
            peers = model.peerCutSuggestion(afterCutting: photoID)
        default:
            return
        }
        guard !peers.isEmpty else { return }
        let mapped = peers.map { PresentationAdapter.asset(from: $0) }
        pendingPeerSuggestion = PeerCullSuggestion(
            anchorAssetID: photoID,
            peerAssets: mapped,
            suggestedDecision: .cut,
            reason: reasonLabel(for: mapped, decision: decision)
        )
    }

    private func reasonLabel(for peers: [AssetPresentation], decision: AssetDecision) -> String {
        let count = peers.count
        switch decision {
        case .keep:
            return "\(count) softer frame\(count == 1 ? "" : "s") from the same subject"
        case .cut:
            return "\(count) similar low-quality frame\(count == 1 ? "" : "s") in this set"
        default:
            return "\(count) similar frame\(count == 1 ? "" : "s")"
        }
    }

    private func advanceWithinGroup(afterDeciding photoID: AssetID, presentation: WorkspacePresentation, model: ProjectViewModel) {
        guard let group = presentation.groups.first(where: { $0.assets.contains(where: { $0.id == photoID }) }) else {
            model.advanceAfterDecisionPublic()
            selectedAssetID = model.cursor
            return
        }
        selectedGroupID = group.id

        let freshGroup = workspacePresentation(model: model).groups.first(where: { $0.id == group.id }) ?? group
        if let next = freshGroup.assets.first(where: { $0.decision == .undecided && $0.id != photoID }) {
            selectedAssetID = next.id
            model.setCursor(next.id)
            _ = PreviewSpine.shared.paint(id: next.id, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
            return
        }

        if let nextGroup = nextGroupWithUndecided(after: group.id, in: presentation.groups) {
            selectedGroupID = nextGroup.id
            if let next = nextGroup.assets.first(where: { $0.decision == .undecided }) ?? nextGroup.assets.first {
                selectedAssetID = next.id
                model.setCursor(next.id)
                _ = PreviewSpine.shared.paint(id: next.id, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
            }
            return
        }

        selectedAssetID = model.cursor ?? photoID
    }

    private func nextGroupWithUndecided(after groupID: String, in groups: [GroupPresentation]) -> GroupPresentation? {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return nil }
        for group in groups.dropFirst(index + 1) {
            if group.assets.contains(where: { $0.decision == .undecided }) {
                return group
            }
        }
        return nil
    }

    func moveAttempt(delta: Int, presentation: WorkspacePresentation, model: ProjectViewModel) {
        let groups = presentation.groups
        guard !groups.isEmpty else { return }
        let currentGroupIndex = groups.firstIndex(where: { $0.id == presentation.selectedGroupID }) ?? 0
        let nextIndex = min(max(currentGroupIndex + delta, 0), groups.count - 1)
        let group = groups[nextIndex]
        selectLead(in: group.id, model: model, presentation: presentation)
    }

    func moveAlternative(delta: Int, presentation: WorkspacePresentation, model: ProjectViewModel) {
        guard let group = presentation.selectedGroup, !group.captureOrderedAssets.isEmpty else { return }
        selectedGroupID = group.id
        let ordered = group.captureOrderedAssets
        let current = presentation.selectedAssetID ?? ordered.first?.id
        guard let current, let index = ordered.firstIndex(where: { $0.id == current }) else { return }
        let next = min(max(index + delta, 0), ordered.count - 1)
        let id = ordered[next].id
        guard id != current else { return }
        selectedAssetID = id
        if model.project != nil { model.setCursor(id) }
        loadDevelop(for: id, model: model)
        _ = PreviewSpine.shared.paint(id: id, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
        prefetchNeighbors(in: group, around: next)
    }

    private func prefetchNeighbors(in group: GroupPresentation, around index: Int) {
        let ordered = group.captureOrderedAssets
        var neighbors: [AssetPresentation] = []
        if index > 0, index < ordered.count {
            neighbors.append(ordered[index])
        }
        let next = index + 1
        if next >= 0, next < ordered.count {
            neighbors.append(ordered[next])
        }
        for asset in neighbors {
            _ = PreviewSpine.shared.silhouetteImage(for: asset.id)
        }
        // Warm decoded previews at the sizes the row and the treatment stage
        // actually display, so stepping to a neighbor is instant.
        let neighborPaths = neighbors.compactMap { $0.previewPath ?? $0.thumbPath }
        ThumbCache.shared.prefetchPaths(neighborPaths, maxPixelSize: 2048)
        let rowPaths = ordered.prefix(8).compactMap { $0.previewPath ?? $0.thumbPath }
        ThumbCache.shared.prefetchPaths(rowPaths, maxPixelSize: 768)
    }

    func enterCrop(for photoID: AssetID, model: ProjectViewModel) {
        guard let photo = model.photo(with: photoID) else { return }
        cropSession = CropSession(photoID: photoID, recipe: photo.effectiveEditRecipe)
    }

    func applyCrop(model: ProjectViewModel) {
        guard let session = cropSession,
              let photo = model.photo(with: session.photoID),
              let snapshot = model.photoRoutingSnapshot(for: session.photoID) else { return }
        let priorEdit = photo.effectiveEditRecipe
        let merged = session.working.merged(into: priorEdit)
        let entry = DecisionLedgerEntry(
            photoID: session.photoID,
            priorTier: snapshot.tier,
            priorFlagged: snapshot.isFlagged,
            priorUncertaintyKind: snapshot.uncertaintyKind,
            priorWhyUncertain: snapshot.whyUncertain,
            applied: .undecided,
            priorRecipe: model.appliedRecipe(for: photo),
            priorEditRecipe: priorEdit
        )
        model.persistEditRecipe(merged, for: session.photoID)
        lastRoundReceipt = RoundReceipt(
            id: UUID(),
            text: "Crop applied",
            entries: [entry],
            priorEmergingOrder: model.emergingSetPresentations().map(\.id)
        )
        cropSession = nil
        LuminaHaptics.decision()
    }

    /// Dismiss latched crop — optionally revert working state to entry baseline (Esc / navigate away).
    @discardableResult
    func dismissCrop(revert: Bool) -> Bool {
        guard cropSession != nil else { return false }
        if revert, var session = cropSession {
            session.revert()
            cropSession = session
        }
        cropSession = nil
        LuminaHaptics.alignment()
        return true
    }

    func cropToggleAspectLock() {
        guard var session = cropSession else { return }
        session.toggleAspectLock()
        cropSession = session
    }

    func cropFlipOrientation() {
        guard var session = cropSession else { return }
        session.flipOrientation()
        cropSession = session
    }

    /// Stage a per-RAW develop proposal for the focused photograph (A key — hi-fi H4).
    func stageDevelopProposal(for photoID: AssetID, model: ProjectViewModel) async {
        guard let photo = model.photo(with: photoID),
              let path = photo.previewPath ?? photo.thumbPath else { return }
        let baseEdit = photo.effectiveEditRecipe
        guard let proposal = await developProposalEngine.propose(imagePath: path, baseRecipe: baseEdit) else {
            LuminaHaptics.light()
            return
        }

        if !workbenchSelection.contains(photoID) {
            workbenchSelection.gather(photoID)
        }
        selectedAssetID = photoID
        model.setCursor(photoID)

        let baseDevelop = model.appliedRecipe(for: photo)
        developOffsets = DevelopAdjustments.from(proposal: proposal, base: baseDevelop)
        treatmentPreviewMode = .current

        guard workbenchSelection.stage(.develop(proposals: [photoID: proposal])) else {
            LuminaHaptics.light()
            return
        }
        refreshStagingCopy(model: model)
        LuminaHaptics.decision()
    }

    func refreshStagingCopy(model: ProjectViewModel) {
        guard workbenchSelection.staged != nil else {
            stagingCopySnapshot = nil
            return
        }
        let presentation = workspacePresentation(model: model)
        stagingCopySnapshot = CopyContractBuilder.snapshot(
            from: workbenchSelection,
            presentation: presentation,
            excludedCount: 0,
            ring: .row,
            isDevelop: workbenchSelection.staged?.isDevelopStaging == true
        )
    }
}
