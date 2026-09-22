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
            case .auto: auto += 1
            case .autoHand, .hand, .sidecar: yours += 1
            }
        }
        return "\(frames) frames · \(moments) moments · \(asShot) as shot · "
            + "\(auto) auto · \(yours) yours · ? keys"
    }

    /// `the set · n` when a set exists, else `all · n`, else `nothing as shot`.
    var autoButtonSubLabel: String {
        let setIDs = finalSetAssetIDs
        if !setIDs.isEmpty {
            let count = setIDs.filter { asShot($0) }.count
            return count > 0 ? "the set · \(count)" : "nothing as shot"
        }
        let count = assets.filter { $0.recipeSource == .shot }.count
        return count > 0 ? "all · \(count)" : "nothing as shot"
    }

    private func asShot(_ id: UUID) -> Bool {
        assets.first(where: { $0.id == id })?.recipeSource == .shot
    }

    /// `A` on the table: the set when there is one, otherwise everything.
    func applyAutoToTable() {
        let setIDs = finalSetAssetIDs
        let targets = setIDs.isEmpty ? assets.map(\.id) : setIDs
        Task { [weak self] in
            guard let self else { return }
            await self.ensureImageStats(for: targets)
            self.applyAuto(to: targets)
        }
    }

    // MARK: - Moments

    /// Seconds between the start of moment `index` and the start of the next one.
    func gapInterval(after index: Int) -> TimeInterval? {
        guard chapters.indices.contains(index), chapters.indices.contains(index + 1) else { return nil }
        guard let start = chapters[index].startedAt,
              let next = chapters[index + 1].startedAt else { return nil }
        return max(0, next.timeIntervalSince(start))
    }

    func momentTimeLabel(_ chapter: ShootChapter) -> String {
        guard let startedAt = chapter.startedAt else { return "Undated" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: startedAt)
    }

    /// What the light was doing, from the hour alone — no location, no almanac.
    /// Deliberately coarse: it orients the photographer, it does not claim precision.
    func momentLightWord(_ chapter: ShootChapter) -> String {
        guard let startedAt = chapter.startedAt else { return "" }
        let hour = Calendar.current.component(.hour, from: startedAt)
        switch hour {
        case 0..<5: return "before sunrise"
        case 5..<7: return "first light"
        case 7..<11: return "morning"
        case 11..<15: return "midday"
        case 15..<18: return "afternoon"
        case 18..<20: return "golden"
        case 20..<22: return "after sunset"
        default: return "night"
        }
    }

    /// `n frames · k bursts`, plus the camera/phone mix when it is mixed.
    func momentCountLine(_ chapter: ShootChapter) -> String {
        let frames = chapter.assetIDs.count
        let bursts = chapter.bursts.filter { $0.frameCount > 1 }.count
        let frameWord = frames == 1 ? "frame" : "frames"
        let burstWord = bursts == 1 ? "burst" : "bursts"
        var line = bursts > 0
            ? "\(frames) \(frameWord) · \(bursts) \(burstWord)"
            : "\(frames) \(frameWord)"
        let phones = chapter.assetIDs.filter { isPhoneFrame($0) }.count
        if phones > 0, phones < frames {
            line += " · \(phones) phone"
        } else if phones == frames, frames > 0 {
            line += " · phone"
        }
        return line
    }

    /// Phone frames carry no RAW original.
    private func isPhoneFrame(_ id: UUID) -> Bool {
        guard let asset = assets.first(where: { $0.id == id }) else { return false }
        let rawExtensions: Set<String> = ["arw", "cr2", "cr3", "nef", "raf", "dng", "orf", "rw2"]
        let ext = (asset.filename as NSString).pathExtension.lowercased()
        return !rawExtensions.contains(ext)
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
        assets.first(where: { $0.id == id })?.cull == .keep
    }

    var setShelfLabel: String {
        let count = finalSetAssetIDs.count
        return count == 0 ? "no set yet" : "set · \(count)"
    }

    // MARK: - Focus route

    /// The word the metadata bar uses for where this frame stands.
    func focusStateWord(for asset: AssetRecord) -> String {
        switch asset.recipeSource {
        case .shot: return "as shot"
        case .auto: return "auto"
        case .autoHand, .hand: return "yours"
        case .sidecar: return "yours · sidecar"
        }
    }

    /// True when the next frame in shoot order belongs to a different moment.
    func startsNewMoment(after assetID: UUID) -> Bool {
        guard let index = assets.firstIndex(where: { $0.id == assetID }),
              assets.indices.contains(index + 1) else { return false }
        let here = ShootChapterArrangement.chapter(containing: assetID, in: chapters)?.id
        let next = ShootChapterArrangement.chapter(containing: assets[index + 1].id, in: chapters)?.id
        return here != next
    }

    /// `1` / `2` / `3` — as shot, auto, yours.
    ///
    /// Switching away from a hand recipe caches it first, so `3` can always return
    /// to it. Auto is only derived when the frame has been measured.
    func pickVersion(_ index: Int, for assetID: UUID) {
        guard let asset = assets.first(where: { $0.id == assetID }) else { return }
        cacheHandRecipeIfNeeded(for: asset)

        switch index {
        case 1:
            applyVersion(.neutral, source: .shot, to: assetID)
        case 2:
            guard let stats = asset.imageStats else {
                Task { [weak self] in
                    guard let self else { return }
                    await self.ensureImageStats(for: [assetID])
                    guard let measured = self.assets.first(where: { $0.id == assetID })?.imageStats,
                          let fresh = self.assets.first(where: { $0.id == assetID }) else { return }
                    self.applyVersion(
                        AutoDevelop.recipe(for: fresh, stats: measured),
                        source: .auto,
                        to: assetID
                    )
                }
                return
            }
            applyVersion(AutoDevelop.recipe(for: asset, stats: stats), source: .auto, to: assetID)
        case 3:
            guard let hand = asset.handRecipe else { return }
            applyVersion(hand, source: .hand, to: assetID)
        default:
            return
        }
    }

    /// Keep the hand recipe before a version switch can overwrite it.
    private func cacheHandRecipeIfNeeded(for asset: AssetRecord) {
        let isHandAuthored = asset.recipeSource == .hand
            || asset.recipeSource == .autoHand
            || asset.recipeSource == .sidecar
        guard isHandAuthored, let current = asset.recipe else { return }
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
