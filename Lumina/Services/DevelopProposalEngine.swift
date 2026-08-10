import Foundation

/// Per-RAW develop proposal — histogram + gray-world behind a swappable protocol (hi-fi H4).
protocol DevelopProposalEngine: Sendable {
    func propose(imagePath: String, baseRecipe: EditRecipe) async -> EditRecipe?
}

/// v1: histogram auto-exposure + gray-world temp/tint — evaluated independently per photograph.
struct HistogramDevelopProposalEngine: DevelopProposalEngine {
    func propose(imagePath: String, baseRecipe: EditRecipe) async -> EditRecipe? {
        guard let suggestion = await AutoDevelop.suggest(imagePath: imagePath) else { return nil }
        let baseDevelop = baseRecipe.asDevelopRecipe
        let offsets = DevelopAdjustments.from(autoSuggestion: suggestion, base: baseDevelop)
        let merged = baseDevelop.applying(offsets)
        return EditRecipe(from: merged, id: baseRecipe.id).updating {
            $0.crop = baseRecipe.crop
            $0.straightenDegrees = baseRecipe.straightenDegrees
            $0.retouch = baseRecipe.retouch
        }
    }
}

extension DevelopAdjustments {
    /// Convert absolute AutoDevelop targets into offsets against the current base recipe.
    static func from(autoSuggestion s: AutoDevelop.Suggestion, base: DevelopRecipe) -> DevelopAdjustments {
        DevelopAdjustments(
            exposure: min(max(s.exposure - base.exposure, -2), 2),
            temperature: min(max(s.kelvin - base.temperature, -2000), 2000),
            tint: min(max(s.tint - base.tint, -50), 50),
            contrast: min(max(s.contrast - base.contrast, -100), 100),
            highlights: min(max(s.highlights - base.highlights, -100), 100),
            shadows: min(max(s.shadows - base.shadows, -100), 100),
            vibrance: min(max(s.vibrance - base.vibrance, -100), 100)
        )
    }

    /// Rail offsets that land on an absolute EditRecipe proposal.
    static func from(proposal: EditRecipe, base: DevelopRecipe) -> DevelopAdjustments {
        DevelopAdjustments(
            exposure: proposal.exposure - base.exposure,
            temperature: proposal.temperature - base.temperature,
            tint: proposal.tint - base.tint,
            contrast: proposal.contrast - base.contrast,
            highlights: proposal.highlights - base.highlights,
            shadows: proposal.shadows - base.shadows,
            whites: proposal.whites - base.whites,
            blacks: proposal.blacks - base.blacks,
            vibrance: proposal.vibrance - base.vibrance,
            saturation: proposal.saturation - base.saturation,
            sharpness: proposal.sharpness - base.sharpness,
            luminanceNR: proposal.luminanceNR - base.luminanceNR
        )
    }
}
