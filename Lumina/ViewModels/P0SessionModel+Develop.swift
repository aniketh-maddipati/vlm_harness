import Foundation

/// `M` carries these from the cursor (README `sync{}`; the word itself is banned in
/// copy, so the surface says *match*). Light, colour and profile travel by default.
nonisolated enum ElasticMatchGroup: String, CaseIterable, Sendable {
    case light
    case color
    case detail
    case crop
    case profile

    static let defaultOn: Set<ElasticMatchGroup> = [.light, .color, .profile]

    /// Copy this group's fields from `source` into `recipe`.
    func copy(from source: EditRecipe, to recipe: inout EditRecipe) {
        switch self {
        case .light:
            recipe.exposure = source.exposure
            recipe.contrast = source.contrast
            recipe.highlights = source.highlights
            recipe.shadows = source.shadows
        case .color:
            recipe.temperature = source.temperature
            recipe.tint = source.tint
            recipe.vibrance = source.vibrance
            recipe.saturation = source.saturation
        case .detail:
            recipe.sharpness = source.sharpness
        case .crop:
            recipe.crop = source.crop
            recipe.cropAspect = source.cropAspect
            recipe.straightenDegrees = source.straightenDegrees
        case .profile:
            recipe.cameraProfile = source.cameraProfile
        }
    }
}

/// One exposed slider in the drawer. Whites, Blacks and Dehaze stay in the schema
/// and the XMP but are not here — the engine renders them inert.
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
    ]

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

    func toggleMatchGroup(_ group: ElasticMatchGroup) {
        if matchGroups.contains(group) {
            matchGroups.remove(group)
        } else {
            matchGroups.insert(group)
        }
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

    /// `to the set · 4` — where `M` would carry the cursor's groups.
    func matchScopeLine(for id: UUID) -> String {
        let count = matchTargetIDs(for: id).count
        let where_: String
        if !selectedAssetIDs.isEmpty {
            where_ = "\(selectedAssetIDs.count) selected"
        } else if peek == .set || isInFinalSet(id) {
            where_ = "the set"
        } else {
            where_ = "the moment"
        }
        return "to \(where_) · \(count)"
    }

    /// The drawer's last line: where this version came from and what a nudge does.
    func developSourceLine(for asset: AssetRecord) -> String {
        switch asset.recipeSource {
        case .shot:
            return "as shot · nudge anything and it becomes yours · A for auto"
        case .auto:
            return "auto from the histogram · nudge to make it yours"
        case .sidecar:
            return "from \(focusFileStem(for: asset)).xmp · the sidecar is the truth · nudges ripple to the group as deltas"
        case .autoHand, .hand:
            return "yours · nudges ripple to the group as deltas · export writes the sidecar"
        }
    }
}
