import Foundation

/// One exposed slider in the always-on Develop rail. Whites, Blacks, Dehaze,
/// Texture and Clarity stay in the schema and the XMP but are not here — the
/// engine renders them inert.
nonisolated struct ElasticDevelopControl: Identifiable, Sendable {
    let id: String
    let name: String
    let keyPath: WritableKeyPath<EditRecipe, Double>
    let range: ClosedRange<Double>
    let step: Double
    let zero: Double

    @MainActor static let exposed: [ElasticDevelopControl] = [
        .init(id: "exposure", name: "Exposure", keyPath: \.exposure,
              range: -ElasticLayout.exposureRange...ElasticLayout.exposureRange, step: ElasticLayout.exposureStep, zero: 0),
        .init(id: "contrast", name: "Contrast", keyPath: \.contrast,
              range: -ElasticLayout.toneRange...ElasticLayout.toneRange, step: 1, zero: 0),
        .init(id: "highlights", name: "Highlights", keyPath: \.highlights,
              range: -ElasticLayout.toneRange...ElasticLayout.toneRange, step: 1, zero: 0),
        .init(id: "shadows", name: "Shadows", keyPath: \.shadows,
              range: -ElasticLayout.toneRange...ElasticLayout.toneRange, step: 1, zero: 0),
        .init(id: "temperature", name: "Temp", keyPath: \.temperature,
              range: ElasticLayout.temperatureMin...ElasticLayout.temperatureMax, step: ElasticLayout.temperatureStep,
              zero: EditRecipe.neutralTemperature),
        .init(id: "tint", name: "Tint", keyPath: \.tint,
              range: -ElasticLayout.toneRange...ElasticLayout.toneRange, step: 1, zero: 0),
        .init(id: "vibrance", name: "Vibrance", keyPath: \.vibrance,
              range: -ElasticLayout.toneRange...ElasticLayout.toneRange, step: 1, zero: 0),
        .init(id: "saturation", name: "Saturation", keyPath: \.saturation,
              range: -ElasticLayout.toneRange...ElasticLayout.toneRange, step: 1, zero: 0),
        .init(id: "sharpness", name: "Sharpness", keyPath: \.sharpness,
              range: 0...ElasticLayout.sharpnessMax, step: 1, zero: 0),
        .init(id: "luminanceNR", name: "Luminance", keyPath: \.luminanceNR,
              range: 0...ElasticLayout.sharpnessMax, step: 1, zero: 0),
    ]

    /// Tone / Color / Detail grouping for the sticky Develop spine.
    var group: P0AdjustmentSection {
        switch id {
        case "exposure", "contrast", "highlights", "shadows": return .light
        case "temperature", "tint", "vibrance", "saturation": return .color
        case "sharpness", "luminanceNR": return .detail
        default: return .light
        }
    }

    /// `+0.35` · `6500K` · `+12` — the prototype's `fmtV`.
    func label(_ value: Double) -> String {
        switch id {
        case "exposure": return String(format: "%+.2f", value)
        case "temperature": return "\(Int(value.rounded()))K"
        default: return String(format: "%+.0f", value)
        }
    }
}

/// The five ratio chips, in the prototype's order.
nonisolated enum ElasticCropRatio: String, CaseIterable, Sendable {
    case original = "orig"
    case threeByTwo = "3:2"
    case fourByFive = "4:5"
    case oneByOne = "1:1"
    case sixteenByNine = "16:9"

    var aspect: EditCropAspect {
        switch self {
        case .original: return .original
        case .threeByTwo: return .threeByTwo
        case .fourByFive: return .fourByFive
        case .oneByOne: return .oneByOne
        case .sixteenByNine: return .sixteenByNine
        }
    }

    /// Width over height; nil is the full frame.
    var ratio: Double? {
        switch self {
        case .original: return nil
        case .threeByTwo: return 3.0 / 2.0
        case .fourByFive: return 4.0 / 5.0
        case .oneByOne: return 1
        case .sixteenByNine: return 16.0 / 9.0
        }
    }

    init?(aspect: EditCropAspect) {
        guard let match = Self.allCases.first(where: { $0.aspect == aspect }) else { return nil }
        self = match
    }

    /// A centred crop in normalised oriented space for a frame whose own aspect
    /// (width over height) is `imageAspect`. The full frame when the ratio is the
    /// frame's own. `P0CropControls.centeredCrop` ignored the frame's aspect — its
    /// 1:1 was a no-op — so it is not salvaged.
    func centeredCrop(imageAspect: Double) -> EditCrop? {
        guard let target = ratio, imageAspect > 0 else { return nil }
        if abs(target - imageAspect) < 1e-6 { return nil }
        if target > imageAspect {
            let height = imageAspect / target
            return EditCrop(x: 0, y: (1 - height) / 2, width: 1, height: height).normalized()
        }
        let width = target / imageAspect
        return EditCrop(x: (1 - width) / 2, y: 0, width: width, height: 1).normalized()
    }
}

@MainActor
extension P0SessionModel {
    /// Shot / Auto / yours tiles are gone. Staged looks use `variationColumnVisible`.
    var versionColumnVisible: Bool { false }

    /// Staged looks sit on the rail until Esc dismisses them or the photograph leaves.
    var variationColumnVisible: Bool {
        peek == nil
            && stagedAutoAssetID == focusedAssetID
            && !stagedAutoVariations.isEmpty
    }

    var hasStagedAutoVariations: Bool {
        stagedAutoAssetID != nil && !stagedAutoVariations.isEmpty
    }

    /// Highlighted means still staged. The accepted look is the quiet one.
    func isAutoVariationHighlighted(_ id: String) -> Bool {
        acceptedAutoVariationID != id
    }

    func variationLabel(for id: String) -> String {
        switch id {
        case "tone": return CopyContract.developVariationTone
        case "lift": return CopyContract.developVariationLift
        case "punch": return CopyContract.developVariationPunch
        default: return id
        }
    }

    /// `A` in inspect — stage the three deterministic looks. Nothing is written yet.
    func stageAutoVariations(
        for assetID: UUID,
        measure: (@MainActor (AssetRecord) async -> ImageStats?)? = nil
    ) {
        guard route == .focus else { return }
        if autoRun != nil || versionAutoAssetID == assetID { return }
        cancelVersionAuto()
        flushPendingEditIfNeeded()
        guard let asset = asset(assetID) else { return }

        if let stats = asset.imageStats {
            installStagedVariations(AutoDevelop.variations(for: asset, stats: stats), assetID: assetID)
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
            self.versionAutoTask = nil
            self.versionAutoRequestID = nil
            self.versionAutoAssetID = nil
            guard let stats = fresh.imageStats else {
                self.versionAutoStatus = "Adjustments unavailable · no measurements"
                return
            }
            self.installStagedVariations(AutoDevelop.variations(for: fresh, stats: stats), assetID: assetID)
        }
    }

    func pickStagedVariation(at index: Int) {
        guard stagedAutoVariations.indices.contains(index) else { return }
        pickStagedVariation(stagedAutoVariations[index].id)
    }

    /// Apply that look and put the photograph in the set. The same look again
    /// clears — out of the set, recipe restored, looks re-staged.
    func pickStagedVariation(_ id: String) {
        guard let assetID = stagedAutoAssetID,
              let variation = stagedAutoVariations.first(where: { $0.id == id }) else { return }
        if acceptedAutoVariationID == id {
            revertAcceptedVariation(assetID)
            acceptedAutoVariationID = nil
            return
        }
        applyStagedVariation(variation, to: assetID)
        if asset(assetID)?.cull != .keep {
            classifySet([assetID])
        }
        acceptedAutoVariationID = id
    }

    /// Esc — unapplied looks vanish and write nothing. An accepted look stays.
    func dismissStagedAutoVariations() {
        stagedAutoVariations = []
        stagedAutoAssetID = nil
        acceptedAutoVariationID = nil
        stagedAutoBaselineRecipe = nil
        stagedAutoBaselineSource = nil
        cancelVersionAuto()
    }

    private func installStagedVariations(_ variations: [AutoVariation], assetID: UUID) {
        stagedAutoVariations = variations
        stagedAutoAssetID = assetID
        acceptedAutoVariationID = nil
        stagedAutoBaselineRecipe = recipe(for: assetID)
        stagedAutoBaselineSource = asset(assetID)?.recipeSource ?? .shot
        versionAutoStatus = nil
    }

    private func applyStagedVariation(_ variation: AutoVariation, to assetID: UUID) {
        guard let current = asset(assetID) else { return }
        let before = recipe(for: assetID)
        guard before.valueFingerprint != variation.recipe.valueFingerprint
                || current.recipeSource != .auto else {
            return
        }
        _ = commitBatchEdit(
            marks: [
                BatchEditMutationCommand.Mark(
                    assetID: assetID,
                    before: before,
                    after: variation.recipe,
                    sourceBefore: current.recipeSource,
                    sourceAfter: .auto
                )
            ],
            label: "Develop"
        )
    }

    private func revertAcceptedVariation(_ assetID: UUID) {
        guard let current = asset(assetID) else { return }
        let after = stagedAutoBaselineRecipe ?? .neutral
        let sourceAfter = stagedAutoBaselineSource ?? .shot
        let before = recipe(for: assetID)
        if before.valueFingerprint != after.valueFingerprint || current.recipeSource != sourceAfter {
            _ = commitBatchEdit(
                marks: [
                    BatchEditMutationCommand.Mark(
                        assetID: assetID,
                        before: before,
                        after: after,
                        sourceBefore: current.recipeSource,
                        sourceAfter: sourceAfter
                    )
                ],
                label: "Develop"
            )
        }
        if asset(assetID)?.cull == .keep {
            classifySet([assetID])
        }
    }

    /// `crs:CameraProfile` values the drawer offers, the prototype's four.
    static let cameraProfiles = ["Camera Standard", "Camera Neutral", "Camera Portrait", "Adobe Color"]

    /// The whole turns and the fine angle, split the way the render graph splits them.
    static func splitStraighten(_ degrees: Double) -> (turns: Double, fine: Double) {
        let turns = (degrees / 90.0).rounded()
        return (turns, degrees - turns * 90)
    }

    func setCropRatio(_ ratio: ElasticCropRatio) {
        guard let id = inspectingAssetID ?? focusedAssetID, let asset = asset(id) else { return }
        let imageAspect = Double(ContactSheetPreparation.aspectRatio(for: asset))
        applyDevelopEdit(label: "Crop") { recipe in
            recipe.cropAspect = ratio.aspect
            recipe.crop = ratio.centeredCrop(imageAspect: imageAspect)
        }
    }

    func setCameraProfile(_ profile: String) {
        applyDevelopEdit(label: "Profile") { $0.cameraProfile = profile }
    }

    // MARK: - Copy

    /// `ripples to N` — the selection when there is one, else the cursor's burst.
    func drawerScopeLine(for id: UUID) -> String {
        "ripples to \(developScopeIDs(for: id).count)"
    }

    /// `original` · `3:2` · `custom · +1.5°` · `90°`. The ratio is named by the
    /// preset that made it; a hand-dragged rect is `custom`.
    func cropSummary(for recipe: EditRecipe) -> String {
        var parts: [String] = []
        if recipe.cropAspect != .original {
            parts.append(ElasticCropRatio(aspect: recipe.cropAspect)?.rawValue ?? "custom")
        } else if let crop = recipe.crop, !crop.isFullFrame {
            parts.append("custom")
        }
        let (turns, fine) = Self.splitStraighten(recipe.straightenDegrees)
        if turns != 0 {
            parts.append("\(Int((turns * 90).truncatingRemainder(dividingBy: 360)))°")
        }
        if abs(fine) >= ElasticLayout.straightenStep / 2 {
            parts.append(Self.angleLabel(fine))
        }
        return parts.isEmpty ? "original" : parts.joined(separator: " · ")
    }

    /// `+1.5°`, always signed.
    static func angleLabel(_ degrees: Double) -> String {
        String(format: "%+.1f°", degrees)
    }

    /// The drawer's last line: where this version came from and what a nudge does.
    func developSourceLine(for asset: AssetRecord) -> String {
        switch asset.recipeSource {
        case .shot:
            return "as shot · nudge anything and it becomes yours · A for auto"
        case .auto:
            return "auto from the histogram · nudge to make it yours"
        case .model:
            return "auto from the model · bounded by the engine · nudge to make it yours"
        case .sidecar:
            return "from \(focusFileStem(for: asset)).xmp · the sidecar is the truth · nudges ripple to the group as deltas"
        case .autoHand, .hand:
            return "yours · nudges ripple to the group as deltas · export writes the sidecar"
        }
    }
}
