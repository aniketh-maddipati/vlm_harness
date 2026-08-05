import Foundation

/// How a photograph relates to a shared treatment recipe.
enum PhotoRecipeLink: Codable, Hashable, Sendable {
    /// Photograph still follows the shared recipe; no local divergence.
    case linked(recipeID: UUID)
    /// Photograph was linked but now carries local overrides that must not be silently overwritten.
    case divergent(recipeID: UUID, local: EditRecipe)
    /// Photograph owns a private recipe (never shared).
    case privateRecipe(EditRecipe)
    /// No treatment assigned — Original / camera default decode.
    case none
}

/// Distinct treatment presentation states (not the same as link state).
enum TreatmentAuthority: String, Codable, Hashable, Sendable {
    /// Camera / demosaic default — recipe ignored.
    case original
    /// Project auto/taste recipe preview (not committed as Current).
    case auto
    /// Staged batch treatment — preview only until commit.
    case staged
    /// Committed treatment for this photograph.
    case current
}

/// Per-photograph edit binding. Original RAW path remains immutable and is never stored here.
struct PhotoEditBinding: Codable, Hashable, Sendable, Identifiable {
    var id: UUID { photoID }
    let photoID: UUID
    var link: PhotoRecipeLink
    var authority: TreatmentAuthority

    init(photoID: UUID, link: PhotoRecipeLink = .none, authority: TreatmentAuthority = .original) {
        self.photoID = photoID
        self.link = link
        self.authority = authority
    }

    /// Resolved recipe for rendering under the given authority.
    /// - Parameters:
    ///   - shared: lookup of shared recipes by id
    ///   - autoRecipe: project Auto/taste recipe when authority == .auto
    ///   - stagedRecipe: batch-staged recipe when authority == .staged
    func resolvedRecipe(
        shared: [UUID: EditRecipe],
        autoRecipe: EditRecipe? = nil,
        stagedRecipe: EditRecipe? = nil
    ) -> EditRecipe {
        switch authority {
        case .original:
            return .neutral
        case .auto:
            return autoRecipe ?? .neutral
        case .staged:
            return stagedRecipe ?? effectiveCommittedRecipe(shared: shared)
        case .current:
            return effectiveCommittedRecipe(shared: shared)
        }
    }

    func effectiveCommittedRecipe(shared: [UUID: EditRecipe]) -> EditRecipe {
        switch link {
        case .none:
            return .neutral
        case .linked(let recipeID):
            return shared[recipeID] ?? .neutral
        case .divergent(_, let local):
            return local
        case .privateRecipe(let recipe):
            return recipe
        }
    }

    var sharedRecipeID: UUID? {
        switch link {
        case .linked(let id), .divergent(let id, _):
            return id
        case .privateRecipe, .none:
            return nil
        }
    }

    var hasLocalDivergence: Bool {
        if case .divergent = link { return true }
        return false
    }

    var isLinkedToShared: Bool {
        if case .linked = link { return true }
        return false
    }
}

/// Store of immutable shared recipes + per-frame bindings.
/// Shared edits propagate only to photographs still `.linked` to that recipe.
struct EditRecipeStore: Codable, Hashable, Sendable {
    var recipes: [UUID: EditRecipe]
    var bindings: [UUID: PhotoEditBinding]

    init(recipes: [UUID: EditRecipe] = [:], bindings: [UUID: PhotoEditBinding] = [:]) {
        self.recipes = recipes
        self.bindings = bindings
    }

    mutating func upsertShared(_ recipe: EditRecipe) {
        recipes[recipe.id] = recipe
    }

    mutating func bindLinked(photoID: UUID, recipeID: UUID) {
        bindings[photoID] = PhotoEditBinding(
            photoID: photoID,
            link: .linked(recipeID: recipeID),
            authority: .current
        )
    }

    /// Update a shared recipe. Only `.linked` photographs pick up the new values.
    /// Divergent / private bindings are untouched.
    mutating func updateSharedRecipe(_ recipe: EditRecipe) {
        recipes[recipe.id] = recipe
    }

    /// Apply a local edit to one photograph.
    /// If it was linked, it becomes divergent (keeps recipeID for UI “shared vs local” labeling).
    mutating func applyLocalEdit(photoID: UUID, recipe: EditRecipe) {
        let existing = bindings[photoID]
        let link: PhotoRecipeLink
        if let sharedID = existing?.sharedRecipeID {
            link = .divergent(recipeID: sharedID, local: recipe)
        } else if case .privateRecipe = existing?.link {
            link = .privateRecipe(recipe)
        } else {
            link = .privateRecipe(recipe)
        }
        bindings[photoID] = PhotoEditBinding(photoID: photoID, link: link, authority: .current)
    }

    /// Re-link a divergent photograph to the shared recipe, discarding local overrides.
    mutating func relinkToShared(photoID: UUID) {
        guard var binding = bindings[photoID], let id = binding.sharedRecipeID else { return }
        binding.link = .linked(recipeID: id)
        binding.authority = .current
        bindings[photoID] = binding
    }

    /// Restore bindings after batch undo — does not silently overwrite unrelated photos.
    mutating func restoreBindings(_ prior: [UUID: PhotoEditBinding]) {
        for (id, binding) in prior {
            bindings[id] = binding
        }
    }

    /// Photographs that still follow a shared recipe (eligible for propagation).
    func linkedPhotoIDs(for recipeID: UUID) -> [UUID] {
        bindings.values.compactMap { binding in
            if case .linked(let id) = binding.link, id == recipeID {
                return binding.photoID
            }
            return nil
        }
    }

    func binding(for photoID: UUID) -> PhotoEditBinding {
        bindings[photoID] ?? PhotoEditBinding(photoID: photoID)
    }

    // MARK: Stable serialization

    static func encodeStable(_ store: EditRecipeStore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(store)
    }

    static func decode(_ data: Data) throws -> EditRecipeStore {
        try JSONDecoder().decode(EditRecipeStore.self, from: data)
    }
}
