import Foundation

/// The deterministic first pass the UI calls "auto".
///
/// Pure function of `ImageStats` plus the asset's existing recipe: the same stats
/// always produce the same recipe, on any machine, in any session. It never reads
/// cull, taste, selection, or wall-clock time, and it never decides anything the
/// photographer can't immediately overwrite by hand.
///
/// Only controls the render graph is honest about are touched. Whites, Blacks,
/// Dehaze, Texture and Clarity stay at 0 — they remain inert in the engine
/// (`docs/DEVELOP_ENGINE.md`), so an auto pass that moved them would be claiming
/// a correction the pixels never receive.
nonisolated struct AutoDevelop {
    /// Mid-tone anchor the exposure correction pulls `ImageStats.mean` toward.
    static let meanAnchor = 0.46
    static let exposureGain = 3.0
    static let exposureLimit = 1.0
    static let brighteningLimit = 0.35
    static let highlightHeadroomBoundary = 0.80
    static let highlightPercentile = 0.98
    static let shadowLiftLimit = 20.0
    static let exposureStep = 0.05
    /// Below this clip fraction a frame counts as "not actually clipping".
    static let clipSignificance = 0.005
    /// Applied when the frame is not clipping at that end — a gentle default curve.
    static let defaultHighlights = 0.0
    static let defaultShadows = 0.0
    static let autoVibrance = 8.0

    /// Tone Auto preserves crop, rotation, profile, and white-balance intent.
    static func recipe(for asset: AssetRecord, stats: ImageStats) -> EditRecipe {
        let base = asset.recipe ?? .neutral
        return base.updating { recipe in
            recipe.exposure = exposure(stats: stats)
            recipe.highlights = highlights(clipFraction: stats.highlightClipFraction)
            recipe.shadows = shadows(clipFraction: stats.shadowClipFraction)
            recipe.vibrance = autoVibrance
            // Tone Auto preserves the complete starting WB intent. The neutral
            // sentinel resolves camera temperature AND tint in the RAW decoder;
            // adopting only stats.nativeTemperature would create a hybrid pair.
            // Geometry is an explicit photographer choice, not part of tone Auto.
            // Inert in the render graph — an auto pass must not pretend otherwise.
            recipe.whites = 0
            recipe.blacks = 0
            recipe.dehaze = 0
        }
    }

    /// Pull the measured mean toward the mid-tone anchor, bounded and quantized
    /// so two near-identical frames in one burst can't land on different values.
    static func exposure(mean: Double) -> Double {
        guard mean.isFinite, (0...1).contains(mean) else { return 0 }
        let raw = (meanAnchor - mean) * exposureGain
        let bounded = min(max(raw, -exposureLimit), brighteningLimit)
        return (bounded / exposureStep).rounded() * exposureStep
    }

    /// Display-space histogram headroom is a conservative veto, not a RAW EV
    /// estimate. A low mean alone cannot distinguish a night scene from underexposure.
    static func exposure(stats: ImageStats) -> Double {
        let proposed = exposure(mean: stats.mean)
        guard proposed > 0 else { return proposed }
        guard stats.highlightClipFraction.isFinite,
              (0...clipSignificance).contains(stats.highlightClipFraction),
              stats.luminanceBins.count == ImageStats.binCount,
              stats.luminanceBins.allSatisfy({ $0 >= 0 }) else { return 0 }
        let total = stats.luminanceBins.reduce(0.0) { $0 + Double($1) }
        guard total > 0 else { return 0 }
        var cumulative = 0.0
        for (index, count) in stats.luminanceBins.enumerated() {
            cumulative += Double(count)
            if cumulative >= total * highlightPercentile {
                let upperEdge = Double(index + 1) / Double(ImageStats.binCount)
                return upperEdge < highlightHeadroomBoundary ? proposed : 0
            }
        }
        return 0
    }

    /// Recover only genuinely clipped highlights; otherwise apply the default curve.
    static func highlights(clipFraction: Double) -> Double {
        guard clipFraction.isFinite, (0...1).contains(clipFraction),
              clipFraction > clipSignificance else { return defaultHighlights }
        return -min(80, clipFraction * 3000)
    }

    /// Lift genuinely crushed shadows; otherwise apply the default curve.
    static func shadows(clipFraction: Double) -> Double {
        guard clipFraction.isFinite, (0...1).contains(clipFraction),
              clipFraction > clipSignificance else { return defaultShadows }
        return min(shadowLiftLimit, clipFraction * 1000)
    }

}
