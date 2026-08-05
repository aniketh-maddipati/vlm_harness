import Foundation

/// Plain-language summary of an extracted develop profile for the sidebar and export payoff.
enum TasteProfileDescription {
    static let lowSourceThreshold = 8

    static func isLowConfidence(sourceCount: Int) -> Bool {
        sourceCount < lowSourceThreshold
    }

    static func lowConfidenceExplanation() -> String {
        "Using a neutral default — point Lumina at a folder with at least \(lowSourceThreshold) edited JPGs from Lightroom to learn your look."
    }

    static func summary(profile: DevelopRecipe, sourceCount: Int) -> String {
        if sourceCount == 0 || !profile.hasSettings {
            return isLowConfidence(sourceCount: sourceCount)
                ? "Neutral default — no edit history found"
                : "Neutral default"
        }

        var traits: [String] = []
        let tempDelta = profile.temperature - 6500
        if tempDelta > 200 { traits.append("Warmer") }
        else if tempDelta < -200 { traits.append("Cooler") }

        if profile.contrast < -8 { traits.append("lower contrast") }
        else if profile.contrast > 8 { traits.append("higher contrast") }

        if profile.shadows > 8 { traits.append("lifted shadows") }
        else if profile.shadows < -8 { traits.append("deeper shadows") }

        if profile.highlights < -8 { traits.append("pulled highlights") }
        else if profile.highlights > 8 { traits.append("brighter highlights") }

        if profile.exposure > 0.15 { traits.append("brighter") }
        else if profile.exposure < -0.15 { traits.append("darker") }

        if profile.vibrance > 8 { traits.append("more vibrant") }
        else if profile.vibrance < -8 { traits.append("muted color") }

        if profile.clarity > 8 { traits.append("more clarity") }
        else if profile.clarity < -8 { traits.append("softer") }

        let body = traits.isEmpty ? "Subtle adjustments" : traits.joined(separator: ", ")
        return "\(body) — from \(sourceCount) edited photo\(sourceCount == 1 ? "" : "s")"
    }
}

extension DevelopRecipe {
    /// Scales extracted offsets from a baseline (typically neutral) by taste strength (0…1.5).
    func withTasteStrength(_ strength: Double, baseline: DevelopRecipe = .neutral) -> DevelopRecipe {
        var r = DevelopRecipe.lerp(baseline, self, t: min(max(strength, 0), 1.5))
        // Heal spots are binary user intent — never scaled by taste strength.
        r.retouch = retouch
        return r
    }
}
