import Foundation

/// Immutable kept-set export, serialized off the visible rendering lane.
nonisolated enum P0AuthoritativeExportService {
    enum ExportError: LocalizedError {
        case renderFailed(String), writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .renderFailed(let name): return "\(name) could not be rendered from its original."
            case .writeFailed(let name): return "\(name) could not be encoded."
            }
        }
    }

    static func export(plan: P0ExportPlan, to destination: URL,
                       progress: @Sendable (P0ExportJobStore.Summary) async -> Void) async throws -> P0ExportJobStore.Summary {
        let store = try P0ExportJobStore.create(plan: plan, destination: destination)
        return await run(store, progress: progress)
    }

    static func resume(root: URL, expectedJobID: UUID? = nil, expectedShootID: UUID? = nil, progress: @Sendable (P0ExportJobStore.Summary) async -> Void) async throws -> P0ExportJobStore.Summary {
        let store = try P0ExportJobStore(root: root)
        guard (expectedJobID == nil || store.manifest.plan.id == expectedJobID),
              (expectedShootID == nil || store.manifest.plan.shootID == expectedShootID) else {
            throw P0ExportJobStore.Failure.invalidPlan
        }
        do { try store.recover() }
        catch { return store.summary(interruption: error.localizedDescription) }
        return await run(store, progress: progress)
    }

    private static func run(_ store: P0ExportJobStore,
                            progress: @Sendable (P0ExportJobStore.Summary) async -> Void) async -> P0ExportJobStore.Summary {
        await progress(store.summary())
        do {
            // Freeze every available source identity before any render. Retrying
            // preserves existing hashes, so a changed original requires a new job.
            for index in store.manifest.entries.indices where store.manifest.entries[index].state == .pending {
                if Task.isCancelled { try store.cancelRemainder(); return store.summary() }
                if store.manifest.entries[index].sourceHash != nil { continue }
                let hash: String
                do { hash = try P0ExportJobStore.hash(URL(fileURLWithPath: store.manifest.plan.items[index].sourcePath)) }
                catch {
                    try store.update(index) { $0.state = .failed; $0.error = error.localizedDescription }
                    continue
                }
                try store.update(index) { $0.sourceHash = hash }
            }
            for index in store.manifest.entries.indices where store.manifest.entries[index].state == .pending {
                if Task.isCancelled { try store.cancelRemainder(); break }
                let item = store.manifest.plan.items[index]
                let original = URL(fileURLWithPath: item.sourcePath)
                let settings = store.manifest.plan.settings
                try store.update(index) { $0.state = .rendering }
                let bytes: Data
                do {
                    guard try P0ExportJobStore.hash(original) == store.manifest.entries[index].sourceHash else {
                        throw P0ExportJobStore.Failure.sourceChanged
                    }
                    guard let bitmap = await DevelopRenderGraph.renderExportBitmap(rawURL: original, photoID: item.assetID, recipe: item.recipe, settings: settings) else {
                        throw ExportError.renderFailed(item.filename)
                    }
                    guard try P0ExportJobStore.hash(original) == store.manifest.entries[index].sourceHash else {
                        throw P0ExportJobStore.Failure.sourceChanged
                    }
                    let encoded = settings.format == .jpeg
                        ? DevelopRenderGraph.exportJPEGData(cgImage: bitmap, quality: settings.quality)
                        : DevelopRenderGraph.exportTIFFData(cgImage: bitmap)
                    guard let encoded, DevelopRenderGraph.validateExport(bytes: encoded, bitmap: bitmap, settings: settings) else {
                        throw ExportError.writeFailed(item.filename)
                    }
                    bytes = encoded
                } catch {
                    try store.update(index) { $0.state = .failed; $0.error = error.localizedDescription }
                    await progress(store.summary())
                    continue
                }
                // Destination/receipt errors stop the job; they are never treated
                // as another failed photograph. Publication may finish on cancel.
                try store.publish(index, bytes: bytes)
                await progress(store.summary())
            }
            return store.summary()
        } catch {
            return store.summary(interruption: error.localizedDescription)
        }
    }
}
