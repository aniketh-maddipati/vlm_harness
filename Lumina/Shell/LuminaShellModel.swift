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
    var selectedAssetID: AssetID?
    var selectedGroupID: String?
    var isFocusMode = false
    var showInspector = false
    var showShortcuts = false

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
        isFocusMode = false
        showInspector = false
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
        // Retain selected asset when switching organization.
        lens = newLens
    }

    func toggleFocus() {
        isFocusMode.toggle()
        if isFocusMode { showInspector = false }
    }

    func toggleInspector() {
        showInspector.toggle()
    }

    /// Escape closes Focus or a transient overlay — never dumps the workspace to Home.
    func handleEscape() -> Bool {
        if isFocusMode {
            isFocusMode = false
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

    func syncSelectionFromModel(_ model: ProjectViewModel) {
        if selectedAssetID == nil {
            selectedAssetID = model.cursor
        }
    }

    func applyDecision(_ decision: AssetDecision, model: ProjectViewModel) {
        guard model.project != nil else { return }
        if let id = selectedAssetID ?? model.cursor {
            model.setCursor(id)
        }
        switch decision {
        case .cut: model.markReject()
        case .keep: model.markKeep()
        case .needsMe: model.toggleFlag()
        case .anchor: model.markHero()
        case .undecided: break
        }
        selectedAssetID = model.cursor
        // Decision mutates project — force adapter refresh on next read.
        invalidateCache()
    }

    func moveAttempt(delta: Int, presentation: WorkspacePresentation, model: ProjectViewModel) {
        let groups = presentation.groups
        guard !groups.isEmpty else { return }
        let currentGroupIndex = groups.firstIndex(where: { $0.id == presentation.selectedGroupID }) ?? 0
        let nextIndex = min(max(currentGroupIndex + delta, 0), groups.count - 1)
        let group = groups[nextIndex]
        selectedGroupID = group.id
        if let id = group.representativeID ?? group.assets.first?.id {
            selectedAssetID = id
            if model.project != nil { model.setCursor(id) }
            _ = PreviewSpine.shared.paint(id: id, inputTime: CFAbsoluteTimeGetCurrent(), held: abs(delta) > 0)
        }
    }

    func moveAlternative(delta: Int, presentation: WorkspacePresentation, model: ProjectViewModel) {
        guard let group = presentation.selectedGroup, !group.assets.isEmpty else { return }
        let current = presentation.selectedAssetID ?? group.assets.first?.id
        guard let current,
              let index = group.assets.firstIndex(where: { $0.id == current }) else { return }
        let next = min(max(index + delta, 0), group.assets.count - 1)
        let id = group.assets[next].id
        selectedAssetID = id
        if model.project != nil { model.setCursor(id) }
        _ = PreviewSpine.shared.paint(id: id, inputTime: CFAbsoluteTimeGetCurrent(), held: false)
    }
}
