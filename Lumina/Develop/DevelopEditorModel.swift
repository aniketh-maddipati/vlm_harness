import AppKit
import CoreImage
import Foundation
import Observation

/// Persistent live-editing model — one instance above set rows / carousel.
///
/// Owns selected photo identity, prepared session stamp, draft + committed
/// recipes, recipe revision, scheduler connection, and presentation state.
/// Rows may send selection intents; they must not create their own editor.
@MainActor
@Observable
final class DevelopEditorModel {
    private(set) var identity: DevelopEditorIdentity?
    private(set) var photoID: UUID?
    private(set) var rawURL: URL?
    private(set) var proxyURL: URL?

    /// Absolute draft recipe — updated synchronously on every slider tick.
    private(set) var draftRecipe: EditRecipe = .neutral
    /// Last committed (mouse-up / photo-switch) recipe.
    private(set) var committedRecipe: EditRecipe = .neutral
    /// Monotonic revision — increments on every draft mutation.
    private(set) var recipeRevision: UInt64 = 0

    var showBefore = false
    var oneToOne = false
    var isInteractive = false
    private(set) var lastInputToVisibleMs: Double = 0
    private(set) var capabilities: PreparedRawSession.Capabilities?
    private(set) var lifecycle = DevelopLifecycleCounters()
    /// Last valid texture — never flash blank between revisions or photo switches.
    private(set) var lastValidImage: CIImage?

    let scheduler: DevelopRenderScheduler

    /// Process-wide init counter for lifecycle proofs.
    private static var totalInits = 0

    init(scheduler: DevelopRenderScheduler = WorkbenchDevelop.scheduler) {
        self.scheduler = scheduler
        Self.totalInits += 1
        lifecycle.editorModelInits = Self.totalInits
        DevelopLiveLog.event("DevelopEditorModel init count=\(Self.totalInits)")
    }

    var displayedRevision: UInt64 {
        guard let photoID else { return 0 }
        return scheduler.displayedRevision[photoID] ?? 0
    }

    var presentedImage: CIImage? {
        if showBefore, let photoID, let before = scheduler.beforeImage(for: photoID) {
            return before
        }
        if let photoID, let img = scheduler.presentedCIImage(for: photoID) {
            return img
        }
        return lastValidImage
    }

    /// Call from the view when the scheduler publishes so we retain the texture.
    func absorbPresentedTexture() {
        if let photoID, let img = scheduler.presentedCIImage(for: photoID) {
            lastValidImage = img
            lastInputToVisibleMs = scheduler.metrics.lastInputToVisibleMs
        }
    }

    var fidelityLabel: String {
        guard let photoID else { return "—" }
        if showBefore { return DevelopFidelityState.beforeOriginal.label }
        return scheduler.fidelityByPhoto[photoID]?.label ?? "—"
    }

    var statusLine: String {
        let i2v = scheduler.metrics.lastInputToVisibleMs
        let p50 = scheduler.metrics.inputToVisiblePercentile(0.50)
        let p95 = scheduler.metrics.inputToVisiblePercentile(0.95)
        return String(
            format: "%@ · rev %llu→%llu · i2v %.0fms p50=%@ p95=%@ · %@",
            isInteractive ? "interactive" : "settled",
            recipeRevision,
            displayedRevision,
            i2v,
            p50.map { String(format: "%.0f", $0) } ?? "—",
            p95.map { String(format: "%.0f", $0) } ?? "—",
            lifecycle.summaryLine
        )
    }

    // MARK: - Selection

    /// Bind the editor to one photograph. Keeps prior texture until the first
    /// valid frame for the new identity arrives.
    func selectPhoto(
        photoID: UUID,
        rawURL: URL?,
        proxyURL: URL?,
        recipe: EditRecipe
    ) {
        let samePhoto = self.photoID == photoID
        self.photoID = photoID
        self.rawURL = rawURL
        self.proxyURL = proxyURL
        draftRecipe = recipe
        committedRecipe = recipe
        if !samePhoto {
            recipeRevision = 0
            showBefore = false
            oneToOne = false
            // Clear identity gate until the new session binds — avoids rejecting
            // the first frames for the newly selected photograph.
            identity = nil
            scheduler.activeEditorIdentity = nil
        }
        guard let rawURL else {
            identity = nil
            scheduler.activeEditorIdentity = nil
            return
        }
        Task { await bindSession(photoID: photoID, rawURL: rawURL, recipe: recipe) }
    }

    private func bindSession(photoID: UUID, rawURL: URL, recipe: EditRecipe) async {
        let session = await PreparedRawSessionRegistry.shared.session(for: photoID, rawURL: rawURL)
        let sessionID = await session.sessionID
        let caps = await session.capabilityReport()
        capabilities = caps.0
        let newIdentity = DevelopEditorIdentity(photoID: photoID, preparedSessionID: sessionID)
        identity = newIdentity
        scheduler.activeEditorIdentity = newIdentity
        scheduler.activeDisplayProfileID = currentDisplayProfileID()
        DevelopLiveLog.event(
            "editor bind photoID=\(photoID.uuidString) sessionID=\(sessionID.uuidString)"
        )
        requestRender(controlName: "select", controlValue: nil, interactive: false)
        await scheduler.warmBeforeAfter(
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: recipe,
            preparedSessionID: sessionID
        )
    }

    func commitDraft() {
        committedRecipe = draftRecipe
        isInteractive = false
    }

    // MARK: - Controls (synchronous draft + revision)

    func setExposure(_ value: Double) { mutate("exposure", value) { $0.exposure = value } }
    func setTemperature(_ value: Double) { mutate("temperature", value) { $0.temperature = value } }
    func setTint(_ value: Double) { mutate("tint", value) { $0.tint = value } }
    func setHighlights(_ value: Double) { mutate("highlights", value) { $0.highlights = value } }
    func setShadows(_ value: Double) { mutate("shadows", value) { $0.shadows = value } }
    func setContrast(_ value: Double) { mutate("contrast", value) { $0.contrast = value } }
    func setSaturation(_ value: Double) { mutate("saturation", value) { $0.saturation = value } }
    func setVibrance(_ value: Double) { mutate("vibrance", value) { $0.vibrance = value } }
    func setLuminanceNR(_ value: Double) { mutate("luminanceNR", value) { $0.luminanceNR = value } }
    func setSharpness(_ value: Double) { mutate("sharpness", value) { $0.sharpness = value } }

    func applyOffsets(_ offsets: DevelopAdjustments, base: DevelopRecipe) {
        let absolute = EditRecipe(from: DevelopEngine.clampRecipe(base.applying(offsets)), id: photoID ?? draftRecipe.id)
        draftRecipe = absolute
        recipeRevision &+= 1
        isInteractive = true
        requestRender(controlName: "offsets", controlValue: offsets.exposure, interactive: true)
    }

    func setDraftRecipe(_ recipe: EditRecipe, controlName: String = "recipe") {
        draftRecipe = recipe
        recipeRevision &+= 1
        isInteractive = true
        requestRender(controlName: controlName, controlValue: nil, interactive: true)
    }

    private func mutate(_ name: String, _ value: Double, _ body: (inout EditRecipe) -> Void) {
        let t0 = CFAbsoluteTimeGetCurrent()
        draftRecipe = draftRecipe.updating(body)
        recipeRevision &+= 1
        isInteractive = true
        let mainMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        DevelopLiveLog.event(
            "slider MainActor set \(name)=\(String(format: "%.3f", value)) "
                + "revision=\(recipeRevision) mainMs=\(String(format: "%.2f", mainMs))"
        )
        requestRender(controlName: name, controlValue: value, interactive: true, inputEventAt: t0)
    }

    private func requestRender(
        controlName: String?,
        controlValue: Double?,
        interactive: Bool,
        inputEventAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    ) {
        guard let photoID, let rawURL else { return }
        let sessionID = identity?.preparedSessionID ?? UUID()
        scheduler.scrub(
            photoID: photoID,
            rawURL: rawURL,
            proxyURL: proxyURL,
            recipe: draftRecipe,
            preparedSessionID: sessionID,
            recipeRevision: recipeRevision,
            displayProfileID: currentDisplayProfileID(),
            inputEventAt: inputEventAt,
            controlName: controlName,
            controlValue: controlValue
        )
    }

    func toggleBeforeAfter() {
        showBefore.toggle()
    }

    func toggleOneToOne() {
        oneToOne.toggle()
        guard let photoID, let rawURL, let identity else { return }
        if oneToOne {
            Task {
                await scheduler.renderOneToOne(
                    photoID: photoID,
                    rawURL: rawURL,
                    proxyURL: proxyURL,
                    recipe: draftRecipe,
                    region: .full,
                    preparedSessionID: identity.preparedSessionID,
                    recipeRevision: recipeRevision
                )
            }
        } else {
            requestRender(controlName: "fit", controlValue: nil, interactive: false)
        }
    }

    private func currentDisplayProfileID() -> String {
        let space = NSScreen.main?.colorSpace?.cgColorSpace
            ?? DevelopColorPolicy.displayColorSpace
        return DevelopColorPolicy.describeColorSpace(space)
    }
}
