import AppKit
import Foundation
import Observation

/// Fixture discovery for the developer-only Develop Lab.
enum DevelopLabFixtures {
    /// Environment / defaults. Override with `LUMINA_DEVELOP_RAW_DIR` or `--develop-raw-dir <path>`.
    static func resolveRawDirectory(arguments: [String] = ProcessInfo.processInfo.arguments) -> URL? {
        if let idx = arguments.firstIndex(of: "--develop-raw-dir"),
           arguments.indices.contains(idx + 1) {
            let url = URL(fileURLWithPath: arguments[idx + 1], isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let env = ProcessInfo.processInfo.environment["LUMINA_DEVELOP_RAW_DIR"], !env.isEmpty {
            let url = URL(fileURLWithPath: env, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let candidates = [
            "/Users/aniketh/Pictures/jeevana_mehendi_2026_MATCHED_RAWS",
            NSHomeDirectory() + "/Pictures/jeevana_mehendi_2026_MATCHED_RAWS",
            NSHomeDirectory() + "/Pictures/LuminaFixtures",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return nil
    }

    static func discoverRAWFiles(in directory: URL, limit: Int = 3) -> [URL] {
        let exts: Set<String> = ["arw", "cr2", "cr3", "nef", "raf", "dng", "orf", "rw2"]
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            if exts.contains(url.pathExtension.lowercased()) {
                urls.append(url)
            }
            if urls.count >= limit { break }
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

struct DevelopLabFrame: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var filename: String { url.lastPathComponent }
}

/// Developer-only Develop Lab state — isolated from Workbench until live-RAW gates pass.
@MainActor
@Observable
final class DevelopLabModel {
    var frames: [DevelopLabFrame] = []
    var leaderID: UUID?
    var selectedIDs: Set<UUID> = []
    var recipe = EditRecipe()
    var store = EditRecipeStore()
    var batch = BatchTreatmentSession()
    var showBefore = false
    var oneToOne = false
    var panOffset: CGSize = .zero
    var fixtureDirectory: URL?
    var fixtureStatusMessage: String = ""
    var liveRAWBlocked: Bool = false
    var commandHeld = false
    var histogram = DevelopHistogram.Bins.empty
    /// Capability probe for the current leader's file — explicit unsupported
    /// states, never silent fakes.
    var leaderCapabilities: PreparedRawSession.Capabilities?
    var capabilityLine: String = ""
    /// Lab-local recipe revision for latest-wins publication.
    private var labRevision: UInt64 = 0

    let scheduler = DevelopRenderScheduler()

    var leader: DevelopLabFrame? {
        frames.first { $0.id == leaderID } ?? frames.first
    }

    var references: [DevelopLabFrame] {
        frames.filter { $0.id != leader?.id }
    }

    var fidelityLabel: String {
        guard let id = leader?.id else { return "—" }
        if showBefore { return DevelopFidelityState.beforeOriginal.label }
        return scheduler.fidelityByPhoto[id]?.label ?? "—"
    }

    var metricsLine: String { scheduler.metrics.summaryLine }

    func bootstrap() {
        let dir = DevelopLabFixtures.resolveRawDirectory()
        fixtureDirectory = dir
        guard let dir else {
            liveRAWBlocked = true
            fixtureStatusMessage = """
            Live RAW validation blocked — no fixture directory found.
            Pass --develop-raw-dir <path> or set LUMINA_DEVELOP_RAW_DIR.
            Expected representative Sony ARW files.
            """
            // Placeholder mats so layout can still be exercised without RAW.
            frames = (0..<3).map { i in
                DevelopLabFrame(id: UUID(), url: URL(fileURLWithPath: "/dev/null/placeholder-\(i).ARW"))
            }
            leaderID = frames.first?.id
            selectedIDs = Set(frames.map(\.id))
            return
        }

        let urls = DevelopLabFixtures.discoverRAWFiles(in: dir, limit: 3)
        guard urls.count >= 2 else {
            liveRAWBlocked = true
            fixtureStatusMessage = "Found fewer than 2 RAW files in \(dir.path). Live validation blocked."
            frames = urls.map { DevelopLabFrame(id: UUID(), url: $0) }
            leaderID = frames.first?.id
            selectedIDs = Set(frames.map(\.id))
            return
        }

        liveRAWBlocked = false
        fixtureStatusMessage = "Loaded \(urls.count) RAW files from \(dir.path)"
        frames = urls.map { DevelopLabFrame(id: UUID(), url: $0) }
        leaderID = frames.first?.id
        selectedIDs = Set(frames.prefix(3).map(\.id))
        syncBatchSelection()
        warmLeader()
    }

    func selectLeader(_ id: UUID) {
        leaderID = id
        selectedIDs.insert(id)
        syncBatchSelection()
        warmLeader()
    }

    func toggleCommandSelect(_ id: UUID) {
        batch.toggleSelection(photoID: id)
        selectedIDs = Set(batch.selectedPhotoIDs)
        if let leader = batch.leaderPhotoID {
            leaderID = leader
        }
        syncBatchSelection()
    }

    func syncBatchSelection() {
        let ids = frames.map(\.id).filter { selectedIDs.contains($0) }
        batch.setSelection(ids, leader: leaderID)
    }

    func scrubRecipe(_ mutate: (inout EditRecipe) -> Void) {
        recipe = recipe.updating(mutate)
        guard let leader else { return }
        // Lab path: bump a local revision so publication converges on latest.
        labRevision &+= 1
        scheduler.scrub(
            photoID: leader.id,
            rawURL: leader.url,
            proxyURL: nil,
            recipe: recipe,
            recipeRevision: labRevision,
            controlName: "lab",
            controlValue: nil
        )
        // Independently render staged siblings against their own RAW — never reuse leader pixels.
        if batch.phase == .staged {
            for frame in frames where selectedIDs.contains(frame.id) && frame.id != leader.id {
                scheduler.scrub(
                    photoID: frame.id,
                    rawURL: frame.url,
                    proxyURL: nil,
                    recipe: recipe,
                    recipeRevision: labRevision
                )
            }
        }
        refreshHistogramSoon()
    }

    func warmLeader() {
        guard let leader, !liveRAWBlocked else { return }
        refreshCapabilities(for: leader)
        labRevision &+= 1
        scheduler.scrub(
            photoID: leader.id,
            rawURL: leader.url,
            proxyURL: nil,
            recipe: recipe,
            recipeRevision: labRevision
        )
        Task {
            await scheduler.warmBeforeAfter(
                photoID: leader.id,
                rawURL: leader.url,
                proxyURL: nil,
                recipe: recipe
            )
            refreshHistogram()
        }
    }

    func toggleBeforeAfter() {
        showBefore.toggle()
    }

    func toggleOneToOne() {
        oneToOne.toggle()
        guard oneToOne, let leader else { return }
        let region = DevelopRenderRegion(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        Task {
            await scheduler.renderOneToOne(
                photoID: leader.id,
                rawURL: leader.url,
                proxyURL: nil,
                recipe: recipe,
                region: region
            )
        }
    }

    func stageBatch(isARepeat: Bool) {
        do {
            _ = try batch.stage(leaderRecipe: recipe, isARepeat: isARepeat)
            // Preview staged recipe on every selected RAW independently.
            for frame in frames where selectedIDs.contains(frame.id) {
                scheduler.scrub(
                    photoID: frame.id,
                    rawURL: frame.url,
                    proxyURL: nil,
                    recipe: recipe,
                    recipeRevision: labRevision
                )
            }
        } catch BatchTreatmentError.emptySelection {
            fixtureStatusMessage = "Cannot stage — empty selection."
        } catch {
            // Auto-repeat / already staged — ignore quietly.
        }
    }

    func noteReturnReleased() {
        batch.noteReturnReleased()
    }

    func confirmBatch(isARepeat: Bool) {
        // UI / second Return: ensure release was observed (Command shelf Commit simulates release).
        if batch.phase == .staged, !batch.awaitingConfirmReturn {
            batch.noteReturnReleased()
        }
        do {
            _ = try batch.confirmCommit(into: &store, isARepeat: isARepeat)
            fixtureStatusMessage = "Batch committed to \(batch.selectedPhotoIDs.count) photographs."
        } catch BatchTreatmentError.emptySelection {
            fixtureStatusMessage = "Cannot commit — empty selection."
        } catch {
            // Not awaiting confirm / auto-repeat.
        }
    }

    func cancelBatch() {
        batch.cancelStaging()
        fixtureStatusMessage = "Staged batch cancelled."
        warmLeader()
    }

    func undoBatch() {
        if batch.undoLastCommit(into: &store) != nil {
            fixtureStatusMessage = "Batch undone as one transaction."
        }
    }

    func applyLocalOverride() {
        guard let leader else { return }
        // Divergent local edit — must not be overwritten by later shared updates.
        store.applyLocalEdit(photoID: leader.id, recipe: recipe.updating { $0.exposure += 0.15 })
        recipe = store.binding(for: leader.id).effectiveCommittedRecipe(shared: store.recipes)
        fixtureStatusMessage = "Local override on \(leader.filename) — shared recipe will not overwrite."
        warmLeader()
    }

    /// Full Lightroom handoff for the leader: 16-bit ProPhoto TIFF + merged XMP
    /// sidecar next to the RAW + verification receipt.
    func handOffLeaderToLightroom() {
        guard let leader, !liveRAWBlocked else { return }
        let recipe = recipe
        fixtureStatusMessage = "Handing off \(leader.filename)…"
        Task { [weak self] in
            do {
                let handoffDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Pictures/LuminaHandoff", isDirectory: true)
                try FileManager.default.createDirectory(at: handoffDir, withIntermediateDirectories: true)
                let stem = leader.url.deletingPathExtension().lastPathComponent
                let tiff = handoffDir.appendingPathComponent(stem + ".tif")
                let result = try await LightroomHandoffService.performHandoff(
                    photoID: leader.id,
                    rawURL: leader.url,
                    recipe: recipe,
                    tiffDestination: tiff
                )
                self?.fixtureStatusMessage =
                    "Handoff \(result.mergeOutcome.rawValue) · \(result.colorSpaceName) · \(tiff.lastPathComponent)"
            } catch {
                self?.fixtureStatusMessage = "Handoff failed: \(error)"
            }
        }
    }

    private func refreshCapabilities(for frame: DevelopLabFrame) {
        Task { [weak self] in
            let session = await PreparedRawSessionRegistry.shared.session(for: frame.id, rawURL: frame.url)
            let (caps, meta) = await session.capabilityReport()
            guard let self else { return }
            self.leaderCapabilities = caps
            var line = caps.summary
            if let meta {
                line += String(format: " · %d×%d", meta.pixelWidth, meta.pixelHeight)
            }
            self.capabilityLine = line
        }
    }

    private var histogramTask: Task<Void, Never>?

    private func refreshHistogramSoon() {
        histogramTask?.cancel()
        histogramTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            refreshHistogram()
        }
    }

    private func refreshHistogram() {
        // Histogram is analysis, not the live preview path — it reads the small
        // settled bitmap; interactive frames don't materialize CPU bitmaps.
        guard let leader,
              let cg = showBefore
                ? scheduler.beforeBitmap(for: leader.id)
                : scheduler.presentedImage(for: leader.id)
        else { return }
        histogram = DevelopHistogram.compute(from: cg)
    }

    /// Live display surface — CIImage straight to the Metal destination.
    func displayImage(for frame: DevelopLabFrame) -> CIImage? {
        if showBefore, frame.id == leader?.id {
            return scheduler.beforeImage(for: frame.id)
        }
        return scheduler.presentedCIImage(for: frame.id)
    }
}
