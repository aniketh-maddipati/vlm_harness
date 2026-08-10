import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ProjectViewModel {
    var project: LuminaProject?
    /// The only persisted session position. It is always a photo identity, never an index.
    var cursor: PhotoID? {
        get { project?.cursorPhotoID }
        set {
            guard var project else { return }
            if let old = project.cursorPhotoID,
               let oldIndex = project.photos.firstIndex(where: { $0.id == old }),
               let newValue,
               let newIndex = project.photos.firstIndex(where: { $0.id == newValue }),
               newIndex > oldIndex {
                let crossedAt = Date()
                for index in oldIndex..<newIndex where project.photos[index].settledAt == nil {
                    project.photos[index].settledAt = crossedAt
                }
            }
            project.cursorPhotoID = newValue
            self.project = project
            persistDebounced()
        }
    }
    /// Ephemeral view preference. Nil is the live canvas.
    var lens: SessionLens?
    var sortMode: SortMode = .similar
    var filter: GridFilter = .all
    var statusMessage = "Import photos to begin."
    var userFacingError: String?
    var isBusy = false
    var isImporting = false
    var importFinishing = false
    var importProgress = ImportProgress.zero
    var importPreviewPhotos: [PhotoRecord] = []
    var showBefore = false
    var compareMix: Double = 1
    var softRender = SoftRenderController()
    var jobBrief: JobBrief = JobBrief()
    var agentLog: [AgentAction] = []
    var agentPlanText = ""
    var sessionSummary: SessionSummary?
    var showSessionSummary = false
    var exportPayoff: ExportPayoffState?
    var showExportPayoff = false
    var canResumeLastProject = false
    var catalogQueue = CatalogQueueState()
    var isCatalogMode = false
    /// Speed Contract debug HUD (⌥`).
    var showSpeedHUD = false
    var speedHUDPulse: Int = 0
    private var catalogBackgroundTask: Task<Void, Never>?

    var selectedPhoto: PhotoRecord? {
        guard let id = cursor else { return nil }
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
        let candidates = clusters
        let order = Dictionary(uniqueKeysWithValues: (project?.photos ?? []).enumerated().map {
            ($0.element.id, $0.offset)
        })
        return candidates.sorted {
            let lhs = $0.photoIDs.compactMap { order[$0] }.min() ?? .max
            let rhs = $1.photoIDs.compactMap { order[$0] }.min() ?? .max
            return lhs < rhs
        }
    }

    var clusters: [PhotoCluster] {
        guard let photos = project?.photos else { return [] }
        return CullEngine.clusters(from: photos)
    }

    var currentCluster: PhotoCluster? {
        guard let clusterID = selectedPhoto?.clusterID else { return nil }
        return reviewClusters.first { $0.id == clusterID }
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

    func photo(with id: UUID) -> PhotoRecord? {
        project?.photos.first { $0.id == id }
    }

    func developOffsets(for photoID: UUID) -> DevelopAdjustments {
        guard let photo = photo(with: photoID) else { return .zero }
        let baseline = extractedProfile.withTasteStrength(tasteStrength)
        return photo.effectiveRecipe.offsets(from: baseline)
    }

    func persistDevelopOffsets(_ offsets: DevelopAdjustments, for photoID: UUID) {
        guard var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == photoID }) else { return }
        let baseline = extractedProfile.withTasteStrength(tasteStrength)
        var next = baseline.applying(offsets)
        // Slider changes must never wipe heal spots.
        next.retouch = project.photos[index].recipe?.retouch ?? []
        project.photos[index].recipe = next
        self.project = project
        persistDebounced()
    }

    /// Mutate only the retouch (heal) spots of a photo, keeping tone/color as-is.
    func updateRetouch(for photoID: UUID, _ mutate: (inout [RetouchSpot]) -> Void) {
        guard var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == photoID }) else { return }
        var recipe = project.photos[index].recipe
            ?? appliedRecipe(for: project.photos[index])
        mutate(&recipe.retouch)
        project.photos[index].recipe = recipe
        self.project = project
        persistDebounced()
    }

    /// Persist an absolute develop recipe (batch treatment across a gathered selection).
    func persistRecipe(_ recipe: DevelopRecipe, for photoID: UUID) {
        persistEditRecipe(EditRecipe(from: recipe), for: photoID)
    }

    /// Persist canonical EditRecipe (tone + geometry + retouch).
    func persistEditRecipe(_ recipe: EditRecipe, for photoID: UUID) {
        guard var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == photoID }) else { return }
        project.photos[index].editRecipe = recipe
        self.project = project
        persistDebounced()
    }

    func clearRecipe(for photoID: UUID) {
        guard var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == photoID }) else { return }
        project.photos[index].recipe = nil
        project.photos[index].adaptReferenceFrame = nil
        project.photos[index].adaptScopeCount = nil
        project.photos[index].isAdaptReference = false
        self.project = project
        persistDebounced()
    }

    /// Persist post-commit adapt provenance for edit-family chips on the table.
    func persistAdaptProvenance(
        referenceFrame: String,
        scopeCount: Int,
        referencePhotoID: UUID,
        photoIDs: [UUID]
    ) {
        guard var project else { return }
        for id in photoIDs {
            guard let index = project.photos.firstIndex(where: { $0.id == id }) else { continue }
            project.photos[index].adaptReferenceFrame = referenceFrame
            project.photos[index].adaptScopeCount = scopeCount
            project.photos[index].isAdaptReference = (id == referencePhotoID)
        }
        self.project = project
        persistDebounced()
    }

    func clearAdaptProvenance(for photoIDs: [UUID]) {
        guard var project else { return }
        for id in photoIDs {
            guard let index = project.photos.firstIndex(where: { $0.id == id }) else { continue }
            project.photos[index].adaptReferenceFrame = nil
            project.photos[index].adaptScopeCount = nil
            project.photos[index].isAdaptReference = false
        }
        self.project = project
        persistDebounced()
    }

    var wholesaleExcludedPhotoIDs: Set<PhotoID> {
        project?.wholesaleExcludedPhotoIDs ?? []
    }

    func addWholesaleExclusion(_ photoID: PhotoID) {
        guard var project else { return }
        project.wholesaleExcludedPhotoIDs.insert(photoID)
        self.project = project
        persistDebounced()
    }

    func removeWholesaleExclusion(_ photoID: PhotoID) {
        guard var project else { return }
        project.wholesaleExcludedPhotoIDs.remove(photoID)
        self.project = project
        persistDebounced()
    }

    func toggleWholesaleExclusion(_ photoID: PhotoID) -> Bool {
        guard var project else { return false }
        let inserted = project.wholesaleExcludedPhotoIDs.insert(photoID).inserted
        if !inserted {
            project.wholesaleExcludedPhotoIDs.remove(photoID)
        }
        self.project = project
        persistDebounced()
        return inserted
    }

    /// Replace the in-memory project after a ledger append (no full reload).
    func replaceProject(_ project: LuminaProject) {
        self.project = project
        persistDebounced()
    }

    /// Kept photographs in draft chronological order for the emerging set / canvas.
    func emergingSetPresentations() -> [AssetPresentation] {
        guard let photos = project?.photos else { return [] }
        return photos
            .filter { $0.tier == .keep }
            .sorted { ($0.capturedAt ?? .distantPast) < ($1.capturedAt ?? .distantPast) }
            .map { PresentationAdapter.asset(from: $0) }
    }

    var cursorPosition: Int {
        guard let cursor, let photos = project?.photos,
              let index = photos.firstIndex(where: { $0.id == cursor }) else { return 0 }
        return index + 1
    }

    var auditPiles: [AuditPile] {
        guard let photos = project?.photos else { return [] }
        let accepted = project?.decisionLedger.reduce(into: [AuditReason: Set<PhotoID>]()) { result, event in
            guard event.kind == .pileAccepted else { return }
            result[event.reason, default: []].formUnion(event.photoIDs)
        } ?? [:]
        var grouped: [AuditReason: [PhotoRecord]] = [:]
        for photo in photos {
            guard let reason = photo.auditReason,
                  accepted[reason]?.contains(photo.id) != true else { continue }
            grouped[reason, default: []].append(photo)
        }
        return AuditReason.allCases.compactMap { reason in
            guard let photos = grouped[reason], !photos.isEmpty else { return nil }
            return AuditPile(
                reason: reason,
                photos: photos.sorted {
                    if $0.cullConfidence != $1.cullConfidence {
                        return $0.cullConfidence < $1.cullConfidence
                    }
                    return $0.cullScore > $1.cullScore
                }
            )
        }
    }

    var isTerminal: Bool {
        guard let photos = project?.photos, let last = photos.last else { return false }
        return cursor == last.id && auditPiles.isEmpty
    }

    var receiptText: String {
        "\(keepCount) keeps · \(totalCount - keepCount) cuts · \(auditPiles.reduce(0) { $0 + $1.photos.count }) to audit"
    }

    var keymapHint: String {
        switch lens {
        case .grid: "F/D browse · Esc canvas"
        case .audit: "F/D move · P rescue · Return accept"
        case nil:
            switch selectedPhoto.map(posture(for:)) {
            case .burst: "F/D burst · P keep · X cut · M audit"
            case .compare: "F/D compare · P keep · X cut · M audit"
            case .single, nil: "F/D move · P keep · X cut · M audit"
            }
        }
    }

    var auditMetrics: [AuditReason: AuditReasonMetrics] {
        guard let project else { return [:] }
        var result: [AuditReason: AuditReasonMetrics] = [:]
        for reason in AuditReason.allCases {
            let accepted = project.decisionLedger.filter {
                $0.kind == .pileAccepted && $0.reason == reason
            }.flatMap(\.photoIDs)
            let rescued = Set(project.decisionLedger.filter {
                $0.kind == .rescued && $0.reason == reason
            }.flatMap(\.photoIDs))
            let seeds = project.auditSeedPhotoIDs.intersection(accepted)
            result[reason] = AuditReasonMetrics(
                proposed: accepted.count,
                rescued: rescued.count,
                seeded: seeds.count,
                seedsCaught: seeds.intersection(rescued).count
            )
        }
        return result
    }

    func seedKnownGoodAuditFixtures(_ photoIDs: Set<PhotoID>) {
        guard var project else { return }
        project.auditSeedPhotoIDs.formUnion(photoIDs)
        self.project = project
        persistDebounced()
    }

    func posture(for photo: PhotoRecord) -> CanvasPosture {
        if let burst = photo.burstID,
           (project?.photos.filter { $0.burstID == burst }.count ?? 0) > 1 {
            return .burst
        }
        return photo.uncertaintyKind == .cullTie ? .compare : .single
    }

    func openAuditForCursor() {
        let pile = auditPiles.first(where: { pile in
            pile.photos.contains { $0.id == cursor }
        }) ?? auditPiles.first
        if let pile { lens = .audit(pile.reason) }
    }

    // MARK: - Import

    func importPhotos(sourceFolder: URL, photoURLs: [URL]?, jpgURL: URL?) async {
        SessionCache.endEditingSession(clearBrowseSpine: true)
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
                // Stop once Meet opens (isImporting → false) so "Grouping similar…" can't stick forever.
                if isImporting {
                    statusMessage = progress.detail
                }
            case .status(let msg):
                if isImporting { statusMessage = msg }
            case .photosReady(let photos, let profile):
                let p = LuminaProject(
                    name: sourceFolder.lastPathComponent,
                    rawFolder: sourceFolder.path,
                    jpgFolder: jpgURL?.path,
                    profile: profile,
                    tasteSourceCount: 0,
                    photos: photos,
                    cursorPhotoID: firstPhotoID(in: photos)
                )
                SessionCache.beginEditingSession(projectName: p.name)
                withAnimation(.easeInOut(duration: 0.4)) {
                    project = p
                    importPreviewPhotos = photos
                }
            case .photosUpdated(let photos):
                // Path/proxy refine only — merge into live session without reshaping clusters.
                mergePathUpdates(from: photos)
            case .refinementReady(let photos):
                applyRefinementAheadOfCursor(photos)
            case .finished(let finished):
                var finished = finished
                finished.collections = ExportService.draftCollections(from: finished.photos)
                finished.cursorPhotoID = project?.cursorPhotoID ?? firstPhotoID(in: finished.photos)
                project = finished
                importPreviewPhotos = finished.photos
                ProjectStore.saveLastProjectName(finished.name)
                withAnimation(.easeInOut(duration: 0.35)) {
                    sortMode = .similar
                    lens = nil
                    isImporting = false
                    importFinishing = false
                    isBusy = false
                }
                let sets = reviewClusters.count
                statusMessage = "\(sets) sets ready"
                warmBrowseSpine(photos: finished.photos)
                // Prefetch first two Meet sets so cards paint instantly.
                let clusters = CullEngine.clusters(from: finished.photos)
                if let first = clusters.first { warmClusterMembers(first) }
                if clusters.count > 1 { warmClusterMembers(clusters[1], paintFocus: false) }
            case .failed(let msg):
                statusMessage = msg
                userFacingError = msg
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

    func restoreCatalogQueueIfNeeded() {
        guard !isCatalogMode else { return }
        Task {
            guard let saved = await CatalogAgent.loadSavedQueue() else { return }
            catalogQueue = saved
            isCatalogMode = true
            jobBrief = saved.brief
            agentPlanText = CatalogAgent.planText(for: saved)
            statusMessage = saved.headline
            resumeBackgroundIndexing()
        }
    }

    func pickCatalogRoot() {
        guard let root = pickFolder(
            message: "Select the parent folder containing your shoot folders (100+ subfolders OK)"
        ) else { return }
        Task { await startCatalogScan(at: root) }
    }

    func startCatalogScan(at root: URL) async {
        isBusy = true
        isCatalogMode = true
        catalogQueue.isScanning = true
        statusMessage = "Scanning shoot folders…"
        defer {
            isBusy = false
            catalogQueue.isScanning = false
        }

        do {
            let state = try await CatalogAgent.scan(root: root, brief: jobBrief)
            catalogQueue = state
            agentPlanText = CatalogAgent.planText(for: state)
            statusMessage = "Found \(state.totalFolders) folders · starting queue"
            await openNextCatalogFolder(autoStart: true)
            resumeBackgroundIndexing()
        } catch {
            statusMessage = error.localizedDescription
            userFacingError = error.localizedDescription
        }
    }

    private func resumeBackgroundIndexing() {
        catalogBackgroundTask?.cancel()
        let pending = catalogQueue.folders.filter { $0.status == .pending }
        guard !pending.isEmpty else { return }

        catalogQueue.isIndexing = true
        let keepRate = jobBrief.resolvedKeepRate(totalPhotos: 1000)
        catalogBackgroundTask = Task {
            await CatalogAgent.runBackgroundIndexing(
                folders: catalogQueue.folders,
                keepRate: keepRate
            ) { [weak self] id, status, error in
                await MainActor.run {
                    guard let self else { return }
                    if let idx = self.catalogQueue.folders.firstIndex(where: { $0.id == id }) {
                        self.catalogQueue.folders[idx].status = status
                        self.catalogQueue.folders[idx].errorMessage = error
                        if status == .indexed {
                            self.catalogQueue.folders[idx].indexedAt = Date()
                        }
                    }
                    self.catalogQueue.isIndexing = self.catalogQueue.folders.contains {
                        $0.status == .pending || $0.status == .indexing
                    }
                    self.agentPlanText = CatalogAgent.planText(for: self.catalogQueue)
                }
            }
            await MainActor.run {
                self.catalogQueue.isIndexing = false
                self.reloadCatalogFoldersFromStore()
            }
        }
    }

    private func reloadCatalogFoldersFromStore() {
        Task {
            let folders = (try? await CatalogStore.shared.allFolders()) ?? catalogQueue.folders
            catalogQueue.folders = folders
            agentPlanText = CatalogAgent.planText(for: catalogQueue)
        }
    }

    func openNextCatalogFolder(autoStart: Bool = false) async {
        let folders = (try? await CatalogStore.shared.allFolders()) ?? catalogQueue.folders
        catalogQueue.folders = folders

        guard let next = CatalogAgent.nextWorkItem(in: catalogQueue.folders) else {
            statusMessage = "Backlog complete · \(catalogQueue.clearedCount)/\(catalogQueue.totalFolders) cleared"
            return
        }

        if next.status == .pending || next.status == .indexing {
            statusMessage = "Indexing \(next.name)…"
            isBusy = true
            defer { isBusy = false }
        }

        do {
            let keepRate = jobBrief.resolvedKeepRate(totalPhotos: max(next.photoCount, 100))
            let loaded = try await CatalogAgent.indexFolder(next, keepRate: keepRate)
            try? await CatalogStore.shared.updateStatus(id: next.id, status: .active)
            await activateCatalogProject(loaded, folder: next, autoStart: autoStart)
        } catch {
            statusMessage = "Could not open \(next.name): \(error.localizedDescription)"
            userFacingError = statusMessage
        }
    }

    private func activateCatalogProject(
        _ loaded: LuminaProject,
        folder: CatalogFolder,
        autoStart: Bool
    ) async {
        catalogQueue.activeFolderID = folder.id
        if let idx = catalogQueue.folders.firstIndex(where: { $0.id == folder.id }) {
            catalogQueue.folders[idx].status = .active
            let stats = CatalogAgent.folderStats(from: loaded)
            catalogQueue.folders[idx].photoCount = stats.photoCount
            catalogQueue.folders[idx].needsYouCount = stats.needsYou
            catalogQueue.folders[idx].keepCount = stats.keepCount
            catalogQueue.folders[idx].setCount = stats.setCount
        }

        var loadedProject = loaded
        PhotoAgentOrchestrator.applyBrief(jobBrief, to: &loadedProject)
        project = loadedProject
        agentLog = []
        sortMode = .similar
        if project?.cursorPhotoID == nil {
            project?.cursorPhotoID = firstPhotoID(in: loadedProject.photos)
        }
        lens = nil
        ProjectStore.saveLastProjectName(loaded.name)
        SessionCache.beginEditingSession(projectName: loaded.name)
        warmBrowseSpine(photos: loadedProject.photos)

        agentPlanText = CatalogAgent.planText(for: catalogQueue)
        let pos = (catalogQueue.activeFolderIndex ?? 0) + 1
        statusMessage = "Folder \(pos)/\(catalogQueue.totalFolders) · \(folder.name) · \(reviewClusters.count) sets"

        if autoStart, reviewClusters.isEmpty {
            onCursorReachedEnd()
        }
    }

    func advanceCatalogQueueAfterExport() {
        guard isCatalogMode, let activeID = catalogQueue.activeFolderID else { return }
        Task {
            try? await CatalogStore.shared.markCleared(id: activeID)
            if let idx = catalogQueue.folders.firstIndex(where: { $0.id == activeID }) {
                catalogQueue.folders[idx].status = .cleared
                catalogQueue.folders[idx].clearedAt = Date()
            }
            catalogQueue.activeFolderID = nil
            agentPlanText = CatalogAgent.planText(for: catalogQueue)
            await openNextCatalogFolder(autoStart: true)
        }
    }

    private func syncActiveCatalogStats() {
        guard isCatalogMode, let activeID = catalogQueue.activeFolderID, let project else { return }
        let stats = CatalogAgent.folderStats(from: project)
        if let idx = catalogQueue.folders.firstIndex(where: { $0.id == activeID }) {
            catalogQueue.folders[idx].photoCount = stats.photoCount
            catalogQueue.folders[idx].needsYouCount = stats.needsYou
            catalogQueue.folders[idx].keepCount = stats.keepCount
            catalogQueue.folders[idx].setCount = stats.setCount
        }
        Task {
            await CatalogAgent.syncStats(for: activeID, project: project)
        }
        agentPlanText = CatalogAgent.planText(for: catalogQueue)
    }

    func resumeLastProject() {
        guard let saved = try? ProjectStore.loadLastProject() else {
            statusMessage = "No saved project found."
            userFacingError = statusMessage
            canResumeLastProject = false
            return
        }
        project = saved
        sortMode = .similar
        if project?.cursorPhotoID == nil {
            project?.cursorPhotoID = firstPhotoID(in: saved.photos)
        }
        lens = nil
        SessionCache.beginEditingSession(projectName: saved.name)
        warmBrowseSpine(photos: saved.photos)
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
            userFacingError = statusMessage
            return
        }
        Task {
            await importPhotos(sourceFolder: root, photoURLs: nil, jpgURL: nil)
        }
    }

    // MARK: - Set navigation

    func jumpToSet(at index: Int) {
        let clusters = reviewClusters
        guard index >= 0, index < clusters.count else { return }
        guard let target = clusters[index].heroID ?? clusters[index].photoIDs.first else { return }
        setCursor(target)
        lens = nil
        statusMessage = clusters[index].whyGrouped
    }

    func openGridOverview() {
        lens = .grid
        if cursor == nil { cursor = displayedPhotos.first?.id }
    }

    func closeGridOverview() {
        lens = nil
    }

    // MARK: - Selection

    func setCursor(_ id: PhotoID) {
        let start = CFAbsoluteTimeGetCurrent()
        cursor = id
        // Speed Contract: never run CI soft-render on browse advance.
        if lens == .grid {
            playSoftRender(for: id)
        } else {
            softRender.mix = 1
        }
        if let photo = project?.photos.first(where: { $0.id == id }) {
            prefetchPhotoDisplay(photo)
        }
        LatencyMetrics.record("navigation.select", milliseconds: (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    /// Browse advance — paint from PreviewSpine sync, commit selection immediately.
    func advanceBrowse(delta: Int, in photos: [PhotoRecord], inputTime: CFAbsoluteTime, held: Bool = false) {
        guard !photos.isEmpty else { return }
        let id = PreviewSpine.shared.advance(
            in: photos,
            from: cursor,
            delta: delta,
            inputTime: inputTime,
            held: held
        )
        if let id {
            cursor = id
            softRender.mix = 1
            if id == project?.photos.last?.id, isTerminal { onCursorReachedEnd() }
        }
    }

    func selectBrowsePhoto(_ id: UUID, in photos: [PhotoRecord], inputTime: CFAbsoluteTime) {
        PreviewSpine.shared.warm(photos: photos, focus: id)
        PreviewSpine.shared.paint(id: id, inputTime: inputTime, held: false)
        cursor = id
        softRender.mix = 1
    }

    func toggleSpeedHUD() {
        showSpeedHUD.toggle()
    }

    func warmBrowseSpine(photos: [PhotoRecord]? = nil) {
        let list = photos ?? project?.photos ?? []
        guard !list.isEmpty else { return }
        PreviewSpine.shared.warm(photos: list, focus: cursor ?? list.first?.id)
    }

    func advanceFrame(held: Bool = false) {
        let t = CFAbsoluteTimeGetCurrent()
        if lens == .grid {
            nextInDisplayedPhotos()
        } else if case .audit(let reason) = lens,
                  let pile = auditPiles.first(where: { $0.reason == reason }) {
            advanceBrowse(delta: 1, in: pile.photos, inputTime: t, held: held)
        } else {
            advanceBrowse(delta: 1, in: project?.photos ?? [], inputTime: t, held: held)
        }
    }

    func retreatFrame(held: Bool = false) {
        let t = CFAbsoluteTimeGetCurrent()
        if lens == .grid {
            previousInDisplayedPhotos()
        } else if case .audit(let reason) = lens,
                  let pile = auditPiles.first(where: { $0.reason == reason }) {
            advanceBrowse(delta: -1, in: pile.photos, inputTime: t, held: held)
        } else {
            advanceBrowse(delta: -1, in: project?.photos ?? [], inputTime: t, held: held)
        }
    }

    private func nextInDisplayedPhotos() {
        let list = displayedPhotos
        guard !list.isEmpty, let current = cursor,
              let index = list.firstIndex(where: { $0.id == current }) else {
            if let first = list.first { setCursor(first.id) }
            return
        }
        setCursor(list[min(index + 1, list.count - 1)].id)
    }

    private func previousInDisplayedPhotos() {
        let list = displayedPhotos
        guard !list.isEmpty, let current = cursor,
              let index = list.firstIndex(where: { $0.id == current }) else { return }
        setCursor(list[max(index - 1, 0)].id)
    }

    func toggleKeep() {
        guard cursor != nil else { return }
        markKeep()
    }

    func toggleReject() {
        guard cursor != nil else { return }
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
            await PhotoImageCache.shared.prefetch(Array(Set(paths)), maxPixelSize: 1600, allowRAW: false)
        }
    }

    func prefetchPhotoDisplay(_ photo: PhotoRecord) {
        if let grid = photo.gridThumbPath {
            ThumbCache.shared.prefetch(grid, maxPixelSize: PhotoImageTier.gridMaxPixelSize, allowRAW: false)
        }
        var paths = [photo.previewPath, photo.sharpPath].compactMap { $0 }

        if lens == .grid {
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
            await PhotoImageCache.shared.prefetch(Array(Set(paths)), maxPixelSize: 1600, allowRAW: false)
            if let proxy = photo.proxyPath {
                await PhotoImageCache.shared.prefetch([proxy], maxPixelSize: nil, allowRAW: true)
            }
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

    func setTier(_ tier: PhotoTier, for photoID: UUID, userInitiated: Bool = true) {
        guard var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == photoID }) else { return }
        let photo = project.photos[index]
        project.photos[index].tier = tier
        project.photos[index].proposedTier = nil
        project.photos[index].userDecidedAt = Date()
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
        }
        self.project = project
        if userInitiated {
            reapplyTasteAndUncertainty()
        }
        refreshExportCollections()
        persistDebounced()
        syncActiveCatalogStats()
    }

    func toggleFlag() {
        guard var project, let id = cursor,
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

    /// Hold — unresolved marker. Leaves keep/reject so the photograph stays in the family.
    func setHold(for photoID: UUID) {
        guard var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == photoID }) else { return }
        project.photos[index].tier = .unranked
        project.photos[index].proposedTier = nil
        project.photos[index].isFlagged = true
        project.photos[index].uncertaintyKind = .cullBorderline
        project.photos[index].whyUncertain = "Held for another look"
        project.photos[index].userDecidedAt = Date()
        self.project = project
        refreshExportCollections()
        persistDebounced()
        syncActiveCatalogStats()
    }

    /// Clear Hold / restore a set-aside photograph to undecided without taste side-effects.
    func clearRoutingDecision(for photoID: UUID) {
        restorePhotoState(photoID: photoID, tier: .unranked, isFlagged: false)
    }

    /// One-step Undo restore — no taste relearning.
    func restorePhotoState(
        photoID: UUID,
        tier: PhotoTier,
        isFlagged: Bool,
        uncertaintyKind: UncertaintyKind = .none,
        whyUncertain: String? = nil
    ) {
        guard var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == photoID }) else { return }
        project.photos[index].tier = tier
        project.photos[index].proposedTier = nil
        project.photos[index].isFlagged = isFlagged
        project.photos[index].uncertaintyKind = isFlagged ? (uncertaintyKind == .none ? .cullBorderline : uncertaintyKind) : .none
        project.photos[index].whyUncertain = isFlagged ? (whyUncertain ?? "Held for another look") : nil
        if tier == .unranked && !isFlagged {
            project.photos[index].userDecidedAt = nil
            project.photos[index].whyAction = nil
        }
        self.project = project
        refreshExportCollections()
        persistDebounced()
        syncActiveCatalogStats()
    }

    func photoRoutingSnapshot(for photoID: UUID) -> (tier: PhotoTier, isFlagged: Bool, uncertaintyKind: UncertaintyKind, whyUncertain: String?)? {
        guard let photo = project?.photos.first(where: { $0.id == photoID }) else { return nil }
        return (photo.tier, photo.isFlagged, photo.uncertaintyKind, photo.whyUncertain)
    }

    func markKeep() {
        guard let id = cursor else { return }
        setTier(.keep, for: id)
        advanceAfterDecision()
    }

    func markReject() {
        guard let id = cursor else { return }
        setTier(.reject, for: id)
        advanceAfterDecision()
    }

    func applyTier(_ tier: PhotoTier, to photoIDs: [UUID]) {
        guard !photoIDs.isEmpty else { return }
        for id in photoIDs {
            setTier(tier, for: id, userInitiated: true)
        }
        if let last = photoIDs.last {
            setCursor(last)
        }
        advanceAfterDecision()
    }

    /// Peers in the same subject set that are lower quality than the kept frame.
    func peerCutSuggestion(afterKeeping photoID: UUID) -> [PhotoRecord] {
        guard let photos = project?.photos else { return [] }
        return PeerCullEngine.cutSuggestion(afterKeeping: photoID, in: photos) ?? []
    }

    func peerCutSuggestion(afterCutting photoID: UUID) -> [PhotoRecord] {
        guard let photos = project?.photos else { return [] }
        return PeerCullEngine.cutSuggestion(afterCutting: photoID, in: photos) ?? []
    }

    func markHero(advance: Bool = true) {
        guard let id = cursor, var project else { return }
        guard let index = project.photos.firstIndex(where: { $0.id == id }) else { return }
        let photo = project.photos[index]
        project.photos[index].isBurstHero = true
        project.photos[index].isClusterHero = true
        project.photos[index].tier = .keep
        project.photos[index].proposedTier = nil
        project.photos[index].userDecidedAt = Date()
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
        refreshExportCollections()
        persistDebounced()
        reapplyTasteAndUncertainty()
        if advance { advanceAfterDecision() }
    }

    func advanceAfterDecisionPublic() {
        advanceAfterDecision()
    }

    private func advanceAfterDecision() {
        guard let photos = project?.photos, !photos.isEmpty else { return }
        let start = cursor.flatMap { id in photos.firstIndex(where: { $0.id == id }) } ?? -1
        if let next = photos.dropFirst(start + 1).first(where: { $0.tier == .unranked || $0.isFlagged }) {
            setCursor(next.id)
        } else if let last = photos.last {
            setCursor(last.id)
            if isTerminal { onCursorReachedEnd() }
        }
    }

    /// Warm PreviewSpine + session thumb cache for a set so Meet/Pick never open cold.
    private func warmClusterMembers(_ cluster: PhotoCluster, paintFocus: Bool = true) {
        let members = cluster.photoIDs.compactMap { id in project?.photos.first { $0.id == id } }
        guard !members.isEmpty else { return }
        PreviewSpine.shared.warm(
            photos: members,
            focus: paintFocus ? (cluster.heroID ?? members.first?.id) : members.first?.id
        )
        ThumbCache.shared.prefetchPhotos(members, maxPixelSize: PhotoImageTier.gridMaxPixelSize)
    }

    /// Rescue is the only per-tile audit mutation. Accepting materializes the pile default.
    func acceptPile(_ reason: AuditReason, rescuedIDs: Set<PhotoID>) {
        guard var project,
              let pile = auditPiles.first(where: { $0.reason == reason }) else { return }
        let proposed = Dictionary(uniqueKeysWithValues: pile.photos.map {
            ($0.id, $0.proposedTier ?? $0.tier)
        })
        let confidence = Dictionary(uniqueKeysWithValues: pile.photos.map { ($0.id, $0.cullConfidence) })
        for index in project.photos.indices where pile.photos.contains(where: { $0.id == project.photos[index].id }) {
            let id = project.photos[index].id
            if rescuedIDs.contains(id) {
                project.photos[index].tier = .keep
                project.photos[index].whyAction = "Rescued from \(reason.title)"
                TasteLearning.learnFromUserDecision(
                    photo: project.photos[index],
                    kind: .keep,
                    projectName: project.name
                )
            } else if let proposal = project.photos[index].proposedTier {
                project.photos[index].tier = proposal
            }
            project.photos[index].proposedTier = nil
            project.photos[index].userDecidedAt = Date()
            project.photos[index].isFlagged = false
            project.photos[index].uncertaintyKind = .none
            project.photos[index].whyUncertain = nil
        }
        if !rescuedIDs.isEmpty {
            project.decisionLedger.append(DecisionEvent(
                kind: .rescued,
                reason: reason,
                photoIDs: Array(rescuedIDs),
                proposedTiers: proposed.filter { rescuedIDs.contains($0.key) },
                confidenceByPhoto: confidence.filter { rescuedIDs.contains($0.key) }
            ))
            let learned = TasteLearning.learnedProfile(
                projectName: project.name,
                fallback: project.profile
            )
            project.profile = learned.0
            project.editProfile = EditRecipe(from: learned.0)
            project.tasteSourceCount = learned.1
        }
        project.decisionLedger.append(DecisionEvent(
            kind: .pileAccepted,
            reason: reason,
            photoIDs: pile.photos.map(\.id),
            proposedTiers: proposed,
            confidenceByPhoto: confidence
        ))
        self.project = project
        refreshExportCollections()
        persistDebounced()
        syncActiveCatalogStats()
        lens = nil
        advanceAfterDecision()
    }

    func onCursorReachedEnd() {
        guard let project else { return }
        syncActiveCatalogStats()
        SessionCache.endEditingSession(clearBrowseSpine: false)
        let feedbackCount = (try? FeedbackStore.load(project: project.name).count) ?? 0
        sessionSummary = PhotoAgentOrchestrator.buildSessionSummary(
            photos: project.photos,
            agentLog: agentLog,
            feedbackCount: feedbackCount
        )
        statusMessage = receiptText
    }

    private func reapplyTasteAndUncertainty() {
        guard var project else { return }
        let library = (try? TasteIndex.load(project: project.name)) ?? []
        TasteRetriever.applyRecipes(to: &project.photos, library: library, baseline: project.profile)
        CullEngine.assignConfidence(&project.photos)
        self.project = project
    }

    func exportCarousel(refine: Bool = false) {
        guard let project else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose export destination folder"
        if refine, let path = IngestPreferences.lastExportFolderPath {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        IngestPreferences.lastExportFolderPath = folder.path

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
                        keepCount: self.keepCount,
                        highlightCount: outcome.carouselImageURLs.count
                    )
                    self.showExportPayoff = true
                    self.persistDebounced()
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.statusMessage = error.localizedDescription
                    self.userFacingError = error.localizedDescription
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

    /// Recompute export collections (carousel burst heroes, etc.) from current tiers.
    private func refreshExportCollections() {
        guard var project else { return }
        project.collections = ExportService.draftCollections(from: project.photos)
        self.project = project
    }

    /// Merge thumb/proxy path updates into the live session without changing cluster identity.
    private func mergePathUpdates(from updates: [PhotoRecord]) {
        guard var live = project else {
            importPreviewPhotos = updates
            return
        }
        let byID = Dictionary(uniqueKeysWithValues: updates.map { ($0.id, $0) })
        for i in live.photos.indices {
            guard let u = byID[live.photos[i].id] else { continue }
            if let p = u.thumbPath { live.photos[i].thumbPath = p }
            if let p = u.gridThumbPath { live.photos[i].gridThumbPath = p }
            if let p = u.proxyPath { live.photos[i].proxyPath = p }
            live.photos[i].previewOrigin = u.previewOrigin
            live.photos[i].previewLongEdge = u.previewLongEdge
        }
        project = live
        importPreviewPhotos = live.photos
        warmBrowseSpine(photos: live.photos)
        if let cluster = currentCluster {
            warmClusterMembers(cluster)
        }
    }

    /// Apply refinement only ahead of the identity cursor. Mutations at or behind it are dropped.
    private func applyRefinementAheadOfCursor(_ staged: [PhotoRecord]) {
        guard var live = project else { return }
        guard let cursor = live.cursorPhotoID,
              let frontier = live.photos.firstIndex(where: { $0.id == cursor }) else {
            live.photos = staged
            live.cursorPhotoID = firstPhotoID(in: staged)
            live.collections = ExportService.draftCollections(from: staged)
            project = live
            importPreviewPhotos = staged
            warmBrowseSpine(photos: staged)
            persistDebounced()
            return
        }

        let protectedIDs = Set(live.photos.enumerated().compactMap { index, photo in
            index <= frontier || photo.settledAt != nil || photo.userDecidedAt != nil ? photo.id : nil
        })
        let liveIDs = Set(live.photos.map(\.id))
        let stagedAhead = staged.filter {
            liveIDs.contains($0.id) && !protectedIDs.contains($0.id)
        }
        let stagedIDs = Set(stagedAhead.map(\.id))
        let missingFromStage = live.photos.filter {
            !protectedIDs.contains($0.id) && !stagedIDs.contains($0.id)
        }
        var stagedMutable = (stagedAhead + missingFromStage)[...]
        var merged: [PhotoRecord] = []
        merged.reserveCapacity(live.photos.count)
        for photo in live.photos {
            if protectedIDs.contains(photo.id) {
                merged.append(photo)
            } else {
                merged.append(stagedMutable.popFirst() ?? photo)
            }
        }
        live.photos = merged
        live.collections = ExportService.draftCollections(from: merged)
        project = live
        importPreviewPhotos = merged
        refreshExportCollections()
        warmBrowseSpine(photos: merged)
        persistDebounced()
    }

    private func firstPhotoID(in photos: [PhotoRecord]) -> PhotoID? {
        photos.first?.id
    }
}
