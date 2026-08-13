import Foundation

// MARK: - CP2 sidecars (open XMP beside originals)

/// Reconciliation between the in-session journal and durable open XMP sidecars.
///
/// **Session authority (D35 / D13):** While a shoot is open, the append-only journal
/// plus in-memory `AssetRecord.recipe` are authoritative. External sidecar edits
/// never overwrite committed session state silently.
///
/// **Durability (D36):** Every edit commit merges develop settings into standard open
/// XMP (`crs:`) beside the original. Sidecars are the interoperable form another
/// tool reads; deleting Lumina loses nothing.
///
/// **Cold open:** When no journal replay applies, mapped `crs:` fields seed `recipe`
/// from the sidecar. Foreign namespaces and properties are never stripped on read or merge-write.
///
/// **Drift:** If managed `crs:` fields change on disk after Lumina wrote them,
/// return `.externalDrift` — session recipe unchanged until quit/reopen.
enum SidecarReconciliation: Equatable, Sendable {
    case sessionAuthoritative
    case seededFromSidecar
    case externalDrift(sidecarHash: String, sessionHash: String)
}

struct SidecarWriteResult: Equatable, Sendable {
    var mergeOutcome: LightroomHandoffService.MergeOutcome
    var managedFieldsHash: String
}

/// Open XMP beside each original — no central catalog, no Lumina-private receipt files.
enum ShootSidecarStore {
    static func sidecarURL(besideOriginal originalURL: URL) -> URL {
        originalURL.deletingPathExtension().appendingPathExtension("xmp")
    }

    /// Cold-open seed: mapped develop fields only; nil when sidecar absent or neutral.
    static func readMappedRecipe(at xmpURL: URL) throws -> EditRecipe? {
        try LightroomHandoffService.readMappedRecipe(at: xmpURL)
    }

    /// Merge-write on edit commit — preserves foreign XMP; no receipt JSON.
    static func writeCommittedEdit(_ recipe: EditRecipe, besideOriginal originalURL: URL) throws -> SidecarWriteResult {
        let xmpURL = sidecarURL(besideOriginal: originalURL)
        let outcome = try LightroomHandoffService.mergeSidecar(recipe: recipe, at: xmpURL)
        guard let hash = try LightroomHandoffService.managedFieldsHash(at: xmpURL) else {
            throw SidecarError.missingManagedHash
        }
        return SidecarWriteResult(mergeOutcome: outcome, managedFieldsHash: hash)
    }

    /// Hash of Lumina-managed crs fields currently on disk — drift detection domain.
    static func managedFieldsHash(at xmpURL: URL) throws -> String? {
        try LightroomHandoffService.managedFieldsHash(at: xmpURL)
    }

    /// Compare session write hash against on-disk sidecar — journal wins when they differ.
    static func reconcileDuringSession(
        sessionRecipe: EditRecipe,
        lastWrittenHash: String?,
        xmpURL: URL
    ) throws -> SidecarReconciliation {
        guard FileManager.default.fileExists(atPath: xmpURL.path) else {
            return .sessionAuthoritative
        }
        guard let diskHash = try managedFieldsHash(at: xmpURL) else {
            return .sessionAuthoritative
        }
        if let lastWrittenHash, diskHash != lastWrittenHash {
            let sessionHash = LightroomHandoffService.hashOfManagedFields(for: sessionRecipe)
            return .externalDrift(sidecarHash: diskHash, sessionHash: sessionHash)
        }
        return .sessionAuthoritative
    }

    /// Files Lumina must not create for CP2 sidecar durability (D36 no private store).
    static func luminaPrivateSidecarArtifacts(besideOriginal originalURL: URL) -> [URL] {
        let base = originalURL.deletingPathExtension()
        return [
            base.appendingPathExtension("lumina-receipt.json"),
            base.appendingPathExtension("xmp.lumina-backup"),
        ]
    }

    static func assertNoLuminaPrivateStore(besideOriginal originalURL: URL) -> Bool {
        luminaPrivateSidecarArtifacts(besideOriginal: originalURL).allSatisfy {
            !FileManager.default.fileExists(atPath: $0.path)
        }
    }
}

enum SidecarError: Error, Equatable, Sendable {
    case missingManagedHash
    case unreadableSidecar
}
