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
    var isRowExpanded = false
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
    private var previewAnimationTask: Task<Void, Never>?
    private var developPersistTask: Task<Void, Never>?

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
    func handleEscape() -> Bool {
        if isFocusMode {
            isFocusMode = false
            return true
        }
        if workspaceStage == .proof {
            setWorkspaceStage(.canvas)
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
        model.setCursor(targetID)

        pendingPeerSuggestion = nil

        switch decision {
        case .cut:
            model.setTier(.reject, for: targetID)
        case .keep:
            model.setTier(.keep, for: targetID)
        case .needsMe:
            model.toggleFlag()
        case .undecided, .anchor:
            break
        }

        invalidateCache()
        refreshSnapshotsIfNeeded(model: model)
        let presentation = workspacePresentation(model: model)
        advanceWithinGroup(afterDeciding: targetID, presentation: presentation, model: model)
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
        var ids: [AssetID] = []
        if index > 0, index < ordered.count {
            ids.append(ordered[index].id)
        }
        let next = index + 1
        if next >= 0, next < ordered.count {
            ids.append(ordered[next].id)
        }
        for id in ids {
            _ = PreviewSpine.shared.silhouetteImage(for: id)
        }
    }
}
