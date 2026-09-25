import Foundation

/// Derived copy and grouping for the Elastic time route.
///
/// Everything here reads existing canonical state — chapters, cull, recipe source,
/// final order — and formats it. Nothing in this file decides or mutates anything
/// except through functions that already own their command boundary.
@MainActor
extension P0SessionModel {

    // MARK: - Header

    /// `{n} frames · {m} moments · {a} as shot · {b} auto · {c} yours · ? keys`
    var elasticHeaderLine: String {
        let frames = assets.count
        let moments = chapters.count
        var asShot = 0
        var auto = 0
        var yours = 0
        for asset in assets {
            switch asset.recipeSource {
            case .shot: asShot += 1
            // A model proposal is the engine's second version too: produced, untouched,
            // not yet yours — it counts as auto and says where it came from.
            case .auto, .model: auto += 1
            case .autoHand, .hand, .sidecar: yours += 1
            }
        }
        return "\(frames) frames · \(moments) moments · \(asShot) as shot · "
            + "\(auto) auto · \(yours) yours · ? keys"
    }

    /// The header's right-aligned line — what the current surface is saying.
    ///
    /// Held before wins, then a selection, then the route's own line.
    var elasticHeadline: String {
        if showingBefore { return "before · everything as shot · release ␣" }
        let selected = selectedAssetIDs.count
        if selected == 0, peek == nil {
            if let run = autoRun { return "Applying adjustments · \(run.scope)" }
            if let receipt = autoReceipt { return receipt.label }
            if versionAutoAssetID != nil { return "Applying adjustments to this photo…" }
            if let versionAutoStatus { return versionAutoStatus }
        }
        if route == .focus, let id = focusedAssetID {
            if selected > 0 {
                return "\(selected) selected · P · X · 1 2 3 apply to all · Esc clears"
            }
            if peek == .set {
                let set = finalSetAssetIDs
                let position = (set.firstIndex(of: id) ?? 0) + 1
                return "\(position) of \(set.count) in the set · release ⇥"
            }
            guard let chapter = ShootChapterArrangement.chapter(containing: id, in: chapters) else {
                return "? keys"
            }
            let related = min(chapter.assetIDs.count - 1, Self.relatedLimit)
            let relatedWord = related > 0 ? "\(related) related" : "alone in this moment"
            return "\(momentTimeLabel(chapter)) · \(momentLightWord(chapter)) · \(relatedWord) · ? keys"
        }
        if selected > 0 { return "\(selected) selected · P to set · X out · Esc clears" }
        return elasticHeaderLine
    }

    /// How many neighbours a similar peek would ever show.
    static let relatedLimit = 8

    /// `road trip · sept 14` — the shoot's name and the day it was made.
    var elasticSessionLabel: String {
        guard let shoot else { return "" }
        let day = assets.compactMap(\.capturedAt).min() ?? shoot.createdAt
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(shoot.name.lowercased()) · \(formatter.string(from: day).lowercased())"
    }

    /// Auto is live while anything it would touch is still as shot.
    var autoButtonEnabled: Bool { autoRun == nil && versionAutoAssetID == nil && autoButtonSubLabel != "nothing as shot" }

    /// `the set · n` when a set exists, else `all · n`, else `nothing as shot`.
    var autoButtonSubLabel: String {
        if let run = autoRun { return run.scope }
        let setIDs = finalSetAssetIDs
        if !setIDs.isEmpty {
            let count = setIDs.filter { asShot($0) }.count
            return count > 0 ? "the set · \(count)" : "nothing as shot"
        }
        let count = assets.filter { $0.recipeSource == .shot }.count
        return count > 0 ? "all · \(count)" : "nothing as shot"
    }

    private func asShot(_ id: UUID) -> Bool {
        asset(id)?.recipeSource == .shot
    }

    /// The set when there is one, otherwise everything. Selection does not change scope.
    func applyAutoToTable(measure: (@MainActor (AssetRecord) async -> ImageStats?)? = nil) {
        guard autoButtonEnabled else { return }
        let setIDs = finalSetAssetIDs
        let targets = setIDs.isEmpty ? assets.map(\.id) : setIDs
        let run = P0AutoRun(id: UUID(), shootID: shoot?.id, contextID: autoContextID,
                            targetIDs: targets, scope: autoButtonSubLabel,
                            sources: Dictionary(uniqueKeysWithValues: targets.compactMap { id in
                                asset(id).map { (id, P0AutoSource($0)) }
                            }), recipeFingerprints: Dictionary(uniqueKeysWithValues: targets.compactMap { id in
                                asset(id).map { (id, ($0.recipe ?? .neutral).valueFingerprint) }
                            }))
        autoReceipt = nil
        autoRun = run
        autoTask = Task { [weak self] in
            guard let self else { return }
            await self.ensureImageStats(for: targets, measure: measure)
            guard !Task.isCancelled, self.autoRun?.id == run.id,
                  self.autoContextID == run.contextID, self.shoot?.id == run.shootID else { return }
            self.flushPendingEditIfNeeded()
            let valid = targets.filter { id in
                self.asset(id).map(P0AutoSource.init) == run.sources[id]
                    && run.sources[id] != nil
            }
            let eligible = valid.filter { id in
                self.asset(id)?.recipeSource == .shot
                    && self.recipe(for: id).valueFingerprint == run.recipeFingerprints[id]
            }
            let protected = valid.count - eligible.count
            let unmeasured = eligible.filter { self.asset($0)?.imageStats == nil }.count
            let changed = self.applyAuto(to: eligible)
            self.autoReceipt = P0AutoReceipt(adjusted: changed,
                unchanged: valid.count - protected - unmeasured - changed,
                unmeasured: unmeasured, protected: protected, skipped: targets.count - valid.count)
            self.autoRun = nil
            self.autoTask = nil
        }
    }

    /// A cancelled decode may finish, but its results cannot touch the next context.
    func cancelAutoWork() {
        cancelVersionAuto()
        autoContextID = UUID()
        autoTask?.cancel()
        autoTask = nil
        autoRun = nil
        autoReceipt = nil
    }

    // MARK: - Moments

    /// Seconds between the start of moment `index` and the start of the next one.
    func gapInterval(after index: Int) -> TimeInterval? {
        let list = chapters
        guard list.indices.contains(index), list.indices.contains(index + 1) else { return nil }
        guard let start = list[index].startedAt,
              let next = list[index + 1].startedAt else { return nil }
        return max(0, next.timeIntervalSince(start))
    }

    func momentTimeLabel(_ chapter: ShootChapter) -> String {
        guard let startedAt = chapter.startedAt else { return "Undated" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: startedAt)
    }

    /// What the light was doing, from the hour alone — no location, no almanac.
    /// Deliberately coarse: it orients the photographer, it does not claim precision.
    func momentLightWord(_ chapter: ShootChapter) -> String {
        guard let startedAt = chapter.startedAt else { return "" }
        let hour = Calendar.current.component(.hour, from: startedAt)
        switch hour {
        case ..<7: return "before sunrise"
        case 7..<10: return "morning"
        case 10..<15: return "midday"
        case 15..<18: return "afternoon"
        case 18..<20: return "golden hour"
        default: return "after sunset"
        }
    }

    /// `n frames · k bursts` — the moment's span line.
    func momentCountLine(_ chapter: ShootChapter) -> String {
        let frames = chapter.assetIDs.count
        let bursts = chapter.bursts.filter { $0.frameCount > 1 }.count
        let frameWord = frames == 1 ? "frame" : "frames"
        let burstWord = bursts == 1 ? "burst" : "bursts"
        return bursts > 0
            ? "\(frames) \(frameWord) · \(bursts) \(burstWord)"
            : "\(frames) \(frameWord)"
    }

    /// `5 camera · 2 phone` — the moment's mix line. Locked video rows stay out.
    func momentMixLine(_ chapter: ShootChapter) -> String {
        let photos = chapter.assetIDs.compactMap { asset($0) }.filter { !$0.isUnsupportedVideo }
        let phones = photos.filter(\.isPhoneBody).count
        let cameras = photos.count - phones
        return [
            cameras > 0 ? "\(cameras) camera" : nil,
            phones > 0 ? "\(phones) phone" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// Phone frames share one tag — sensed Make/Model or a hand mark both land here.
    func isPhoneFrame(_ id: UUID) -> Bool {
        asset(id)?.isPhoneBody ?? false
    }

    /// Hand phone mark. Same glyph and mix-line treatment as sensing; clears back
    /// to sensed when the photographer marks the same state again.
    @discardableResult
    func setManualPhoneBody(_ id: UUID, isPhone: Bool?) -> Bool {
        guard let index = assetIndex(id) else { return false }
        assets[index].manualIsPhone = isPhone
        return true
    }

    /// The phone button. On only when every frame is already a phone. That press
    /// takes the category off. Otherwise the press marks every frame as phone,
    /// so a phone run leaves the camera stack.
    @discardableResult
    func classifyPhone(_ ids: [UUID]) -> Int {
        var seen: Set<UUID> = []
        let known = ids.filter { seen.insert($0).inserted && asset($0) != nil }
        guard !known.isEmpty else { return 0 }
        let takingOff = known.allSatisfy(isPhoneFrame)
        for id in known {
            setManualPhoneBody(id, isPhone: takingOff ? false : true)
        }
        return known.count
    }

    /// Toggle hand phone mark: unmarked → phone → clear (back to sensed).
    @discardableResult
    func toggleManualPhoneBody(_ id: UUID) -> Bool {
        guard let asset = asset(id) else { return false }
        let next: Bool? = switch asset.manualIsPhone {
        case .none: true
        case .some(true): nil
        case .some(false): true
        }
        return setManualPhoneBody(id, isPhone: next)
    }

    // MARK: - Bursts

    /// Click a stack to open it in place; click again to close it.
    func toggleBurstOpen(_ burstID: String) {
        leanedBurstID = leanedBurstID == burstID ? nil : burstID
    }

    // MARK: - Set

    /// The kept set in presentation order — custom order when the photographer
    /// set one, chronological kept order otherwise.
    var finalSetAssetIDs: [UUID] {
        let custom = shoot?.finalSetOrder.assetIDs ?? []
        if !custom.isEmpty { return custom }
        return assets.filter { $0.cull == .keep }.map(\.id)
    }

    func isInFinalSet(_ id: UUID) -> Bool {
        asset(id)?.cull == .keep
    }

    /// `Export`, then `✓ written` once the set is on disk.
    var elasticExportLabel: String {
        if isExporting { return "Exporting…" }
        return exportSummary?.allCompleted == true ? "✓ written" : "Export"
    }

    /// The receipt band under the shelf, once an export has landed.
    var elasticExportReceipt: (written: String, folder: String)? {
        guard let summary = exportSummary else { return nil }
        let folder = (summary.root.path as NSString).abbreviatingWithTildeInPath
        return ("\(summary.completed) of \(summary.total) written", folder)
    }

    // MARK: - Focus route

    /// `14:02` — when this frame was taken, in the status bar's own format.
    func focusTimeLabel(for asset: AssetRecord) -> String {
        guard let capturedAt = asset.capturedAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: capturedAt)
    }

    /// The file without its extension — the status bar never names the container.
    func focusFileStem(for asset: AssetRecord) -> String {
        (asset.filename as NSString).deletingPathExtension
    }

    /// Which of the three versions the frame is showing: 1 shot · 2 auto · 3 yours.
    func versionIndex(for asset: AssetRecord) -> Int {
        switch asset.recipeSource {
        case .shot: return 1
        case .auto, .model: return 2
        case .autoHand, .hand, .sidecar: return 3
        }
    }

    /// The version's own words, as the status bar and drawer title say them.
    func versionLabel(for asset: AssetRecord) -> String {
        switch asset.recipeSource {
        case .shot: return "as shot"
        case .auto: return "auto"
        case .model: return "auto · from the model"
        case .autoHand: return "auto + your hand"
        case .hand: return "yours"
        case .sidecar: return "yours · from sidecar"
        }
    }

    /// The status bar's last word: set membership, then the version — or `before`.
    func focusStateWord(for asset: AssetRecord) -> String {
        if showingBefore { return "before" }
        let mark: String? = asset.cull == .keep ? "in the set" : asset.cull == .reject ? "out" : nil
        return [mark, versionLabel(for: asset)].compactMap { $0 }.joined(separator: " · ")
    }

    /// Histogram readout: `12% black 3% clipped +0.50 ev`, only what is true.
    func histogramReadout(for asset: AssetRecord) -> String {
        guard let stats = asset.imageStats else { return "" }
        var parts: [String] = []
        if stats.shadowClipFraction > Self.clipReportFraction {
            parts.append("\(Int((stats.shadowClipFraction * 100).rounded()))% black")
        }
        if stats.highlightClipFraction > Self.clipReportFraction {
            parts.append("\(Int((stats.highlightClipFraction * 100).rounded()))% clipped")
        }
        if let recipe = asset.recipe, recipe.hasSettings, !showingBefore {
            parts.append(String(format: "%+.2f ev", recipe.exposure))
        }
        return parts.joined(separator: " ")
    }

    /// Clipping below this share of the frame is not worth a word or a tick.
    static let clipReportFraction = 0.02

    func showsShadowClipTick(for asset: AssetRecord) -> Bool {
        (asset.imageStats?.shadowClipFraction ?? 0) > Self.clipReportFraction
    }

    func showsHighlightClipTick(for asset: AssetRecord) -> Bool {
        (asset.imageStats?.highlightClipFraction ?? 0) > Self.clipReportFraction
    }

    /// How far the drawn histogram slides once a frame is edited.
    ///
    /// The bins are measured off the neutral decode and never re-measured for a
    /// recipe; the readout instead shifts them by what the tone move would do, so
    /// the shape stays honest about the capture and still tracks the edit. Held
    /// `before` shows the measurement unshifted, because that is what before means.
    func histogramBinShift(for asset: AssetRecord) -> Int {
        guard !showingBefore, let recipe = asset.recipe, recipe.hasSettings else { return 0 }
        let moved = recipe.exposure * Self.histogramExposureBins
            + recipe.shadows * Self.histogramShadowBins
        return Int(moved.rounded())
    }

    /// One stop of exposure walks the histogram four bins; shadows barely move it.
    static let histogramExposureBins = 4.0
    static let histogramShadowBins = 0.02

    /// True when the next frame in shoot order belongs to a different moment.
    func startsNewMoment(after assetID: UUID) -> Bool {
        guard let index = assetIndex(assetID),
              assets.indices.contains(index + 1) else { return false }
        return chapterID(containing: assetID) != chapterID(containing: assets[index + 1].id)
    }

    /// `1` / `2` / `3` — as shot, auto, yours.
    ///
    /// Switching away from a hand recipe caches it first, so `3` can always return
    /// to it. Auto is only derived when the frame has been measured.
    func pickVersion(_ index: Int, for assetID: UUID,
                     measure: (@MainActor (AssetRecord) async -> ImageStats?)? = nil) {
        guard (1...3).contains(index) else { return }
        if index == 2, autoRun != nil || versionAutoAssetID == assetID { return }
        cancelVersionAuto()
        let pendingHand = isEditGestureActive && gestureAssetID == assetID
            && workingRecipe?.valueFingerprint != gestureBaselineRecipe?.valueFingerprint
            ? workingRecipe : nil
        flushPendingEditIfNeeded()
        guard let asset = asset(assetID) else { return }
        cacheHandRecipeIfNeeded(for: asset, pendingHand: pendingHand)

        switch index {
        case 1:
            applyVersion(.neutral, source: .shot, to: assetID)
        case 2:
            if let stats = asset.imageStats {
                applyVersion(AutoDevelop.recipe(for: asset, stats: stats), source: .auto, to: assetID)
                versionAutoStatus = "Adjustments applied to this photo"
                return
            }
            let requestID = UUID()
            let context = autoContextID
            let shootID = shoot?.id
            let focusID = focusedAssetID
            let identity = P0AutoSource(asset)
            let recipe = (asset.recipe ?? .neutral).valueFingerprint
            let source = asset.recipeSource
            versionAutoRequestID = requestID
            versionAutoAssetID = assetID
            versionAutoTask = Task { [weak self] in
                guard let self else { return }
                await self.ensureImageStats(for: [assetID], measure: measure)
                guard !Task.isCancelled, self.versionAutoRequestID == requestID else { return }
                guard self.autoContextID == context, self.shoot?.id == shootID,
                      self.focusedAssetID == focusID, let fresh = self.asset(assetID),
                      P0AutoSource(fresh) == identity,
                      (fresh.recipe ?? .neutral).valueFingerprint == recipe,
                      fresh.recipeSource == source else {
                    self.cancelVersionAuto()
                    return
                }
                self.clearVersionAutoState()
                guard let stats = fresh.imageStats else {
                    self.versionAutoStatus = "Adjustments unavailable · no measurements"
                    return
                }
                self.applyVersion(AutoDevelop.recipe(for: fresh, stats: stats), source: .auto, to: assetID)
                self.versionAutoStatus = "Adjustments applied to this photo"
            }
        case 3:
            guard let hand = self.asset(assetID)?.handRecipe else { return }
            applyVersion(hand, source: .hand, to: assetID)
        default: break
        }
    }

    func cancelVersionAuto() {
        versionAutoTask?.cancel()
        clearVersionAutoState()
    }

    private func clearVersionAutoState() {
        versionAutoTask = nil
        versionAutoRequestID = nil
        versionAutoAssetID = nil
        versionAutoStatus = nil
    }

    /// Keep the hand recipe before a version switch can overwrite it.
    private func cacheHandRecipeIfNeeded(for asset: AssetRecord, pendingHand: EditRecipe?) {
        let isHandAuthored = asset.recipeSource == .hand
            || asset.recipeSource == .autoHand
            || asset.recipeSource == .sidecar
        guard let current = pendingHand ?? (isHandAuthored ? asset.recipe : nil) else { return }
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        assets[index].handRecipe = current
        if var shoot {
            shoot.assets = assets
            self.shoot = shoot
        }
    }

    private func applyVersion(_ recipe: EditRecipe, source: RecipeSource, to assetID: UUID) {
        applyEditMutation({ $0 = recipe }, assetID: assetID)
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
        assets[index].recipeSource = source
        if var shoot {
            shoot.assets = assets
            self.shoot = shoot
        }
    }
}
