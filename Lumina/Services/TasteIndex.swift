import Foundation

struct TasteEntry: Codable, Hashable {
    var filename: String
    var path: String
    var recipe: DevelopRecipe
    var embedding: [Float]?
}

enum TasteIndex {
    static func save(entries: [TasteEntry], project: String) throws {
        let url = try ProjectStore.projectDirectory(for: project).appendingPathComponent("taste_index.json")
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url, options: .atomic)
    }

    static func load(project: String) throws -> [TasteEntry] {
        let url = try ProjectStore.projectDirectory(for: project).appendingPathComponent("taste_index.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TasteEntry].self, from: data)
    }
}

enum TasteRetriever {
    static func applyRecipes(
        to photos: inout [PhotoRecord],
        library: [TasteEntry],
        baseline: DevelopRecipe
    ) {
        guard !library.isEmpty else {
            for index in photos.indices where photos[index].tier == .keep {
                var recipe = baseline
                recipe.confidence = 0.4
                recipe.sourceNeighbors = ["baseline"]
                photos[index].recipe = recipe
                photos[index].editConfidence = 0.4
                photos[index].tasteMatch = 0.5
            }
            return
        }

        for index in photos.indices {
            guard photos[index].tier == .keep || photos[index].isFlagged else { continue }
            let result = retrieve(for: photos[index], library: library, baseline: baseline)
            photos[index].recipe = result.recipe
            photos[index].editConfidence = result.recipe.confidence
            photos[index].tasteMatch = result.tasteMatch
        }
    }

    private static func retrieve(
        for photo: PhotoRecord,
        library: [TasteEntry],
        baseline: DevelopRecipe
    ) -> (recipe: DevelopRecipe, tasteMatch: Double) {
        guard let embedding = photo.embedding else {
            var r = baseline
            r.confidence = 0.45
            r.sourceNeighbors = ["baseline-no-embed"]
            // Scene prior
            if photo.faceDetected {
                r.exposure += 0.05
                r.shadows += 5
                r.vibrance += 5
            }
            return (r, 0.4)
        }

        let scored: [(TasteEntry, Float)] = library.compactMap { entry in
            guard let e = entry.embedding, e.count == embedding.count else { return nil }
            return (entry, EmbeddingService.l2Distance(embedding, e))
        }.sorted { $0.1 < $1.1 }

        let k = min(3, scored.count)
        guard k > 0 else {
            var r = baseline
            r.confidence = 0.4
            return (r, 0.4)
        }

        let top = Array(scored.prefix(k))
        let weights = top.map { max(0.001, 1.0 / Double($0.1 + 0.05)) }
        var recipe = weightedAverage(top.map(\.0.recipe), weights: weights)

        // Scene conditioning
        if photo.faceDetected {
            recipe.shadows = min(recipe.shadows + 8, 100)
            recipe.vibrance = min(recipe.vibrance + 4, 100)
        } else {
            recipe.highlights = max(recipe.highlights - 5, -100)
            recipe.dehaze = min(recipe.dehaze + 5, 100)
        }

        let bestDist = Double(top[0].1)
        let confidence = min(max(1.0 - bestDist * 1.8, 0.25), 0.95)
        recipe.confidence = confidence
        recipe.sourceNeighbors = top.map(\.0.filename)
        let tasteMatch = confidence
        return (recipe, tasteMatch)
    }

    private static func weightedAverage(_ recipes: [DevelopRecipe], weights: [Double]) -> DevelopRecipe {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return recipes.first ?? .neutral }
        // Absolute fields must average from 0 — starting from `.neutral` (6500K) double-counted Kelvin
        // and pushed white balance into extreme territory (looked like "distorted" grades).
        var r = DevelopRecipe(
            exposure: 0, temperature: 0, tint: 0, contrast: 0,
            highlights: 0, shadows: 0, whites: 0, blacks: 0,
            texture: 0, clarity: 0, dehaze: 0, vibrance: 0, saturation: 0,
            sharpness: 0, luminanceNR: 0
        )
        for (i, recipe) in recipes.enumerated() {
            let w = weights[i] / sum
            r.exposure += recipe.exposure * w
            r.temperature += recipe.temperature * w
            r.tint += recipe.tint * w
            r.contrast += recipe.contrast * w
            r.highlights += recipe.highlights * w
            r.shadows += recipe.shadows * w
            r.whites += recipe.whites * w
            r.blacks += recipe.blacks * w
            r.texture += recipe.texture * w
            r.clarity += recipe.clarity * w
            r.dehaze += recipe.dehaze * w
            r.vibrance += recipe.vibrance * w
            r.saturation += recipe.saturation * w
            r.sharpness += recipe.sharpness * w
            r.luminanceNR += recipe.luminanceNR * w
        }
        r.temperature = min(max(r.temperature, 2500), 10000)
        r.tint = min(max(r.tint, -50), 50)
        return r
    }
}

