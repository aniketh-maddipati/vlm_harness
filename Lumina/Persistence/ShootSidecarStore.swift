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
/// **Relaunch authority (single winner, no silent disagreement):**
/// 1. Clean shutdown, XMP and `shoot.json` agree → agreed mapped recipe.
/// 2. Journal newer than sidecar → journal (crash window before XMP durability).
/// 3. Sidecar newer than shoot cache → sidecar; catalog is catch-up only.
/// 4. External XMP changed while closed → sidecar adopted; XMP is not rewritten.
/// 5. Shoot cache exists, sidecar missing → journal then catalog; XMP is not created.
/// 6. Sidecar exists, Application Support deleted → sidecar (then journal if newer).
/// 7. Application Support exists, source drive returns → same as 1–6 once originals
///    are readable; offline, catalog only accelerates navigation.
///
/// Recover never writes XMP. `shoot.json` must not silently keep a conflicting
/// recipe when a newer valid sidecar is readable.
///
/// **In-session drift:** If managed `crs:` fields change on disk after Lumina wrote
/// them, return `.externalDrift` — session recipe unchanged until quit/reopen.
enum SidecarReconciliation: Equatable, Sendable {
    case sessionAuthoritative
    case externalDrift(sidecarHash: String, sessionHash: String)
}

/// Cold-open / relaunch winner between catalog+journal memory and the beside-file sidecar.
struct SidecarOpenOutcome: Equatable, Sendable {
    enum Winner: Equatable, Sendable {
        case agreed
        case journalCrashWindow
        case sidecarDurableReceipt
        case sidecarMissing
        case sidecarUnreadable
    }

    var winner: Winner
    /// Recipe to keep on the asset. Recover applies this only for `.sidecarDurableReceipt`.
    var recipe: EditRecipe?
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

    /// Relaunch compare: journal covers the in-flight crash window; a sidecar that is
    /// not older than that window is the durable receipt. Never writes XMP.
    static func reconcileOnOpen(
        existingRecipe: EditRecipe?,
        lastJournalEditAt: Date?,
        xmpURL: URL
    ) -> SidecarOpenOutcome {
        guard FileManager.default.fileExists(atPath: xmpURL.path) else {
            return SidecarOpenOutcome(winner: .sidecarMissing, recipe: existingRecipe)
        }
        let diskHash: String
        do {
            guard let hash = try managedFieldsHash(at: xmpURL) else {
                return SidecarOpenOutcome(winner: .sidecarUnreadable, recipe: existingRecipe)
            }
            diskHash = hash
        } catch {
            return SidecarOpenOutcome(winner: .sidecarUnreadable, recipe: existingRecipe)
        }
        let existingHash = LightroomHandoffService.hashOfManagedFields(for: existingRecipe ?? .neutral)
        if existingHash == diskHash {
            return SidecarOpenOutcome(winner: .agreed, recipe: existingRecipe)
        }
        let sidecarTime = (try? xmpURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        if let journalAt = lastJournalEditAt, let sidecarTime, journalAt > sidecarTime {
            return SidecarOpenOutcome(winner: .journalCrashWindow, recipe: existingRecipe)
        }
        let sidecarRecipe = try? readMappedRecipe(at: xmpURL)
        return SidecarOpenOutcome(winner: .sidecarDurableReceipt, recipe: sidecarRecipe)
    }

    /// Apply relaunch sidecar authority after journal replay. Does not write XMP.
    @discardableResult
    static func applyOpenReconciliation(
        into shoot: inout ShootRecord,
        journalRecords: [ShootJournalRecord]
    ) -> [UUID: SidecarOpenOutcome] {
        var lastEditAt: [UUID: Date] = [:]
        for record in journalRecords where record.kind == .editCommit {
            lastEditAt[record.assetID] = record.recordedAt
        }
        var outcomes: [UUID: SidecarOpenOutcome] = [:]
        for index in shoot.assets.indices {
            let asset = shoot.assets[index]
            let originalURL = URL(fileURLWithPath: asset.source.originalPath)
            guard FileManager.default.fileExists(atPath: originalURL.path) else { continue }
            let outcome = reconcileOnOpen(
                existingRecipe: asset.recipe,
                lastJournalEditAt: lastEditAt[asset.id],
                xmpURL: sidecarURL(besideOriginal: originalURL)
            )
            outcomes[asset.id] = outcome
            if case .sidecarDurableReceipt = outcome.winner {
                shoot.assets[index].recipe = outcome.recipe?.hasSettings == true ? outcome.recipe : nil
            }
        }
        return outcomes
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
