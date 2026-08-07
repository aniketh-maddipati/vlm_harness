import Foundation
import ImageIO
import CoreGraphics

/// Factual preparation progress shown in the contact-sheet toolbar.
struct ContactSheetPreparationStatus: Equatable, Sendable {
    var discoveredCount: Int = 0
    var assetCount: Int = 0
    var previewReadyCount: Int = 0
    var metadataReadyCount: Int = 0
    var unsupportedCount: Int = 0
    var skippedDuplicateCount: Int = 0
    var missingOriginalCount: Int = 0
    var phaseDetail: String = "Idle"
    var isPreparingPreviews: Bool = false
    var isPreparingMetadata: Bool = false
    var folderMissing: Bool = false

    var toolbarLine: String {
        var parts: [String] = ["\(assetCount) photos"]
        if isPreparingPreviews {
            parts.append("previews \(previewReadyCount)/\(max(assetCount, 1))")
        } else if previewReadyCount > 0 {
            parts.append("\(previewReadyCount) previews")
        }
        if isPreparingMetadata {
            parts.append("dates…")
        } else if metadataReadyCount > 0, metadataReadyCount < assetCount {
            parts.append("dates \(metadataReadyCount)/\(assetCount)")
        }
        if unsupportedCount > 0 {
            parts.append("\(unsupportedCount) unsupported")
        }
        if skippedDuplicateCount > 0 {
            parts.append("\(skippedDuplicateCount) dupes")
        }
        if missingOriginalCount > 0 {
            parts.append("\(missingOriginalCount) missing")
        }
        if folderMissing {
            parts.append("drive offline — cached previews")
        }
        return parts.joined(separator: " · ")
    }
}

enum ContactSheetEvent: Sendable {
    case opened(shoot: ShootRecord, status: ContactSheetPreparationStatus)
    case assetsReplaced([AssetRecord], status: ContactSheetPreparationStatus)
    case assetsInserted([AssetRecord], status: ContactSheetPreparationStatus)
    case previewsUpdated([AssetRecord], status: ContactSheetPreparationStatus)
    case metadataMerged([AssetRecord], status: ContactSheetPreparationStatus)
    case status(ContactSheetPreparationStatus)
    case failed(String)
}

/// Incremental contact-sheet preparation — discover → open → visible previews → rest → EXIF.
/// Does not run tiering, taste, faces, aesthetics, grouping, or full RAW decode storms.
nonisolated enum ContactSheetPreparation {
    private static var previewConcurrency: Int {
        min(max(ProcessInfo.processInfo.activeProcessorCount * 2, 8), 16)
    }

    /// Open an existing shoot by name without rediscovery when assets are already cataloged.
    static func openExisting(
        shootName: String,
        visibleWindowHint: Int = 48
    ) -> AsyncStream<ContactSheetEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await runOpenExisting(
                        shootName: shootName,
                        visibleWindowHint: visibleWindowHint,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Discover a folder (or reopen catalog) and prepare the contact sheet incrementally.
    static func openFolder(
        _ folderURL: URL,
        shootName: String? = nil,
        visibleWindowHint: Int = 48
    ) -> AsyncStream<ContactSheetEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await runOpenFolder(
                        folderURL: folderURL,
                        shootName: shootName,
                        visibleWindowHint: visibleWindowHint,
                        continuation: continuation
                    )
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Existing shoot

    private static func runOpenExisting(
        shootName: String,
        visibleWindowHint: Int,
        continuation: AsyncStream<ContactSheetEvent>.Continuation
    ) async throws {
        let openStart = CFAbsoluteTimeGetCurrent()
        var shoot = try ShootStore.loadShoot(id: shootName)
        var status = ContactSheetPreparationStatus()
        status.assetCount = shoot.assets.count
        status.discoveredCount = shoot.assets.count
        status.previewReadyCount = shoot.assets.filter { ($0.gridThumbPath ?? $0.thumbPath) != nil }.count
        status.metadataReadyCount = shoot.assets.filter { $0.capturedAt != nil }.count
        status.missingOriginalCount = shoot.assets.filter { $0.source.availability == .missing }.count
        status.phaseDetail = "Opening \(shoot.name)…"

        var access: (url: URL, didStartAccess: Bool)?
        if let raw = shoot.rawFolder {
            do {
                access = try SecurityScopedAccess.resolveFolder(from: raw)
                shoot = refreshAvailability(shoot, folderURL: access!.url)
                status.folderMissing = false
            } catch {
                status.folderMissing = true
                status.phaseDetail = "Drive offline — using cached previews"
                shoot.assets = shoot.assets.map { asset in
                    var copy = asset
                    copy.source.availability = .missing
                    return copy
                }
                status.missingOriginalCount = shoot.assets.count
            }
        } else {
            status.folderMissing = true
        }

        continuation.yield(.opened(shoot: shoot, status: status))
        LatencyMetrics.record(
            "p0.folder_to_first_paint",
            milliseconds: (CFAbsoluteTimeGetCurrent() - openStart) * 1000
        )

        defer {
            if let access {
                SecurityScopedAccess.stopIfNeeded(access.url, didStartAccess: access.didStartAccess)
            }
        }

        guard !status.folderMissing, let folderURL = access?.url else {
            status.isPreparingPreviews = false
            status.isPreparingMetadata = false
            continuation.yield(.status(status))
            continuation.finish()
            return
        }

        // Fill missing previews only — never re-score or re-tier.
        try await preparePreviews(
            shoot: &shoot,
            folderURL: folderURL,
            prioritizeFirst: visibleWindowHint,
            status: &status,
            continuation: continuation
        )

        await prepareMetadata(
            shoot: &shoot,
            folderURL: folderURL,
            status: &status,
            continuation: continuation
        )

        try savePreservingLiveMutations(shoot)
        continuation.finish()
    }

    // MARK: - Folder open

    private static func runOpenFolder(
        folderURL: URL,
        shootName: String?,
        visibleWindowHint: Int,
        continuation: AsyncStream<ContactSheetEvent>.Continuation
    ) async throws {
        let openStart = CFAbsoluteTimeGetCurrent()
        let name = shootName ?? folderURL.lastPathComponent
        let started = folderURL.startAccessingSecurityScopedResource()
        defer { SecurityScopedAccess.stopIfNeeded(folderURL, didStartAccess: started) }

        var shoot = try ShootStore.createOrOpenShoot(from: folderURL, name: name)
        if shoot.rawFolder?.bookmarkData == nil {
            shoot.rawFolder?.bookmarkData = SecurityScopedAccess.bookmark(for: folderURL)
        }

        // Reopen without rediscovery when the catalog already has assets for this folder.
        if !shoot.assets.isEmpty {
            var status = ContactSheetPreparationStatus()
            status.assetCount = shoot.assets.count
            status.discoveredCount = shoot.assets.count
            status.previewReadyCount = shoot.assets.filter { ($0.gridThumbPath ?? $0.thumbPath) != nil }.count
            status.metadataReadyCount = shoot.assets.filter { $0.capturedAt != nil }.count
            status.missingOriginalCount = shoot.assets.filter { $0.source.availability == .missing }.count
            status.phaseDetail = "Reopened \(shoot.name)"
            continuation.yield(.opened(shoot: shoot, status: status))
            LatencyMetrics.record(
                "p0.folder_to_first_paint",
                milliseconds: (CFAbsoluteTimeGetCurrent() - openStart) * 1000
            )

            try await preparePreviews(
                shoot: &shoot,
                folderURL: folderURL,
                prioritizeFirst: visibleWindowHint,
                status: &status,
                continuation: continuation
            )
            await prepareMetadata(
                shoot: &shoot,
                folderURL: folderURL,
                status: &status,
                continuation: continuation
            )
            try savePreservingLiveMutations(shoot)
            continuation.finish()
            return
        }

        var status = ContactSheetPreparationStatus()
        status.phaseDetail = "Discovering…"
        continuation.yield(.status(status))

        let discovery = MediaFormats.discoverPhotos(at: folderURL)
        status.discoveredCount = discovery.discoveredCount
        status.unsupportedCount = discovery.skipped.filter { $0.reason == .unsupported || $0.reason == .video }.count
        status.skippedDuplicateCount = discovery.skipped.filter { $0.reason == .duplicate }.count

        let existingByKey = Dictionary(uniqueKeysWithValues: shoot.assets.map { ($0.sourceKey, $0.id) })
        let gridDir = try ShootStore.cacheDirectory(for: shoot.name, tier: "grid512")
        let previewDir = try ShootStore.cacheDirectory(for: shoot.name, tier: "preview")

        // Stable asset records first — no previews required to open the sheet.
        var records: [AssetRecord] = []
        records.reserveCapacity(discovery.importable.count)
        for url in discovery.importable {
            let relative = AssetIdentity.relativePath(file: url, root: folderURL)
            let volume = AssetIdentity.volumeIdentifier(for: url)
            let size = AssetIdentity.fileSize(of: url)
            let sourceKey = AssetIdentity.sourceKey(
                volumeID: volume,
                relativePath: relative,
                fileSize: size,
                capturedAt: nil
            )
            let assetID = AssetIdentity.resolveID(sourceKey: sourceKey, preserved: existingByKey[sourceKey])
            let source = SourceReference.make(fileURL: url, rootURL: folderURL)
            records.append(
                AssetRecord(
                    id: assetID,
                    sourceKey: sourceKey,
                    source: source,
                    filename: url.lastPathComponent,
                    cull: .undecided,
                    fileSize: size
                )
            )
        }

        // Chronological placeholder: filename sort until EXIF arrives.
        records.sort { lhs, rhs in
            chronologicalLess(lhs, rhs)
        }

        shoot.assets = records
        status.assetCount = records.count
        status.phaseDetail = "\(records.count) photos"
        status.isPreparingPreviews = true

        // Open the workspace before preview extraction completes.
        continuation.yield(.opened(shoot: shoot, status: status))
        LatencyMetrics.record(
            "p0.folder_to_first_paint",
            milliseconds: (CFAbsoluteTimeGetCurrent() - openStart) * 1000
        )

        // Persist catalog early so reopen skips rediscovery.
        try ShootStore.saveShoot(shoot)

        try await preparePreviews(
            shoot: &shoot,
            folderURL: folderURL,
            prioritizeFirst: visibleWindowHint,
            status: &status,
            continuation: continuation,
            gridDir: gridDir,
            previewDir: previewDir
        )

        await prepareMetadata(
            shoot: &shoot,
            folderURL: folderURL,
            status: &status,
            continuation: continuation
        )

        try savePreservingLiveMutations(shoot)
        continuation.finish()
    }

    // MARK: - Previews

    private static func preparePreviews(
        shoot: inout ShootRecord,
        folderURL: URL,
        prioritizeFirst: Int,
        status: inout ContactSheetPreparationStatus,
        continuation: AsyncStream<ContactSheetEvent>.Continuation,
        gridDir: URL? = nil,
        previewDir: URL? = nil
    ) async throws {
        let grid = try gridDir ?? ShootStore.cacheDirectory(for: shoot.name, tier: "grid512")
        let preview = try previewDir ?? ShootStore.cacheDirectory(for: shoot.name, tier: "preview")

        status.isPreparingPreviews = true
        let indices = Array(shoot.assets.indices)
        let priority = Array(indices.prefix(prioritizeFirst))
        let rest = Array(indices.dropFirst(prioritizeFirst))

        let firstPreviewStart = CFAbsoluteTimeGetCurrent()
        var firstPreviewRecorded = false

        func extractChunk(_ chunk: [Int]) async {
            await withTaskGroup(of: (Int, AssetRecord).self) { group in
                for index in chunk {
                    let asset = shoot.assets[index]
                    group.addTask {
                        var updated = asset
                        let rawURL = URL(fileURLWithPath: asset.source.originalPath)
                        let exists = FileManager.default.fileExists(atPath: rawURL.path)
                        updated.source.availability = exists ? .available : .missing

                        let previewURL = preview.appendingPathComponent(AssetIdentity.cacheStem(for: asset.id) + ".jpg")
                        let gridURL = grid.appendingPathComponent(AssetIdentity.cacheStem(for: asset.id) + ".jpg")

                        let legacyStem = rawURL.deletingPathExtension().lastPathComponent
                        // Migrate legacy stem-keyed caches once.
                        migrateLegacyCache(
                            from: preview.appendingPathComponent(legacyStem + ".jpg"),
                            to: previewURL
                        )
                        migrateLegacyCache(
                            from: grid.appendingPathComponent(legacyStem + ".jpg"),
                            to: gridURL
                        )

                        if exists {
                            let extracted = PreviewExtractor.extractBrowsePreview(
                                to: previewURL,
                                from: rawURL,
                                maxPixelSize: 1600,
                                minLongEdge: 800
                            )
                            if extracted.success, !FileManager.default.fileExists(atPath: gridURL.path) {
                                // 1200 keeps Retina grid cells sharp; 768 upscaled reads grainy.
                                _ = PreviewExtractor.downscaleJPEG(from: previewURL, to: gridURL, maxPixelSize: 1200)
                            }
                            updated.previewOrigin = extracted.origin
                            updated.previewLongEdge = extracted.longEdge
                        }

                        if FileManager.default.fileExists(atPath: previewURL.path) {
                            updated.thumbPath = previewURL.path
                        }
                        if FileManager.default.fileExists(atPath: gridURL.path) {
                            updated.gridThumbPath = gridURL.path
                        } else if updated.thumbPath != nil {
                            updated.gridThumbPath = updated.thumbPath
                        }
                        return (index, updated)
                    }
                }
                for await (index, updated) in group {
                    shoot.assets[index] = updated
                }
            }
        }

        for chunk in priority.chunked(into: previewConcurrency) {
            guard !Task.isCancelled else { return }
            await extractChunk(chunk)
            status.previewReadyCount = shoot.assets.filter { ($0.gridThumbPath ?? $0.thumbPath) != nil }.count
            status.missingOriginalCount = shoot.assets.filter { $0.source.availability == .missing }.count
            status.phaseDetail = "Previews \(status.previewReadyCount)/\(status.assetCount)"
            if !firstPreviewRecorded, status.previewReadyCount > 0 {
                firstPreviewRecorded = true
                LatencyMetrics.record(
                    "p0.first_usable_preview",
                    milliseconds: (CFAbsoluteTimeGetCurrent() - firstPreviewStart) * 1000
                )
            }
            continuation.yield(.previewsUpdated(shoot.assets, status: status))
        }

        for chunk in rest.chunked(into: previewConcurrency) {
            guard !Task.isCancelled else { return }
            await extractChunk(chunk)
            status.previewReadyCount = shoot.assets.filter { ($0.gridThumbPath ?? $0.thumbPath) != nil }.count
            status.missingOriginalCount = shoot.assets.filter { $0.source.availability == .missing }.count
            status.phaseDetail = "Previews \(status.previewReadyCount)/\(status.assetCount)"
            continuation.yield(.previewsUpdated(shoot.assets, status: status))
        }

        status.isPreparingPreviews = false
        status.phaseDetail = "\(status.assetCount) photos"
        continuation.yield(.status(status))
        try? savePreservingLiveMutations(shoot)
    }

    // MARK: - Metadata

    private static func prepareMetadata(
        shoot: inout ShootRecord,
        folderURL: URL,
        status: inout ContactSheetPreparationStatus,
        continuation: AsyncStream<ContactSheetEvent>.Continuation
    ) async {
        status.isPreparingMetadata = true
        status.phaseDetail = "Reading dates…"
        continuation.yield(.status(status))

        let files = shoot.assets.map { URL(fileURLWithPath: $0.source.originalPath) }
        let dates = await Task.detached(priority: .utility) {
            ExifToolService.batchCaptureDates(
                in: folderURL,
                extensions: MediaFormats.exiftoolExtensions,
                files: files
            )
        }.value

        guard !Task.isCancelled else { return }

        // Merge by identity — never invent new IDs or drop decisions/recipes.
        for i in shoot.assets.indices {
            let path = shoot.assets[i].source.originalPath
            let name = shoot.assets[i].filename
            if let date = dates[path] ?? dates[name] {
                shoot.assets[i].capturedAt = date
            }
        }

        // Re-sort chronologically while identity/cull/recipe stay intact.
        shoot.assets.sort { chronologicalLess($0, $1) }
        status.metadataReadyCount = shoot.assets.filter { $0.capturedAt != nil }.count
        status.isPreparingMetadata = false
        status.phaseDetail = "\(status.assetCount) photos"
        continuation.yield(.metadataMerged(shoot.assets, status: status))
    }

    // MARK: - Helpers

    /// Persist preview/metadata progress without clobbering cull/recipe writes from the live session.
    private static func savePreservingLiveMutations(_ prepared: ShootRecord) throws {
        guard let disk = try? ShootStore.loadShoot(id: prepared.name) else {
            try ShootStore.saveShoot(prepared)
            return
        }
        var merged = prepared
        let liveByID = Dictionary(uniqueKeysWithValues: disk.assets.map { ($0.id, $0) })
        for i in merged.assets.indices {
            guard let live = liveByID[merged.assets[i].id] else { continue }
            merged.assets[i].cull = live.cull
            merged.assets[i].recipe = live.recipe
            merged.assets[i].userDecidedAt = live.userDecidedAt
            merged.assets[i].isFlagged = live.isFlagged
        }
        merged.finalSetOrder = disk.finalSetOrder
        merged.workspace = disk.workspace
        merged.exportHistory = disk.exportHistory
        merged.batchHistory = disk.batchHistory
        try ShootStore.saveShoot(merged)
    }

    static func chronologicalLess(_ lhs: AssetRecord, _ rhs: AssetRecord) -> Bool {
        switch (lhs.capturedAt, rhs.capturedAt) {
        case let (l?, r?):
            if l != r { return l < r }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return lhs.filename.localizedStandardCompare(rhs.filename) == .orderedAscending
    }

    static func aspectRatio(for asset: AssetRecord) -> CGFloat {
        if let path = asset.gridThumbPath ?? asset.thumbPath,
           let (w, h) = jpegPixelSize(at: path), w > 0, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        // Neutral placeholder until a preview exists — not a forced crop.
        return 1.5
    }

    static func jpegPixelSize(at path: String) -> (Int, Int)? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard w > 0, h > 0 else { return nil }
        return (w, h)
    }

    private static func migrateLegacyCache(from legacy: URL, to identityURL: URL) {
        guard !FileManager.default.fileExists(atPath: identityURL.path),
              FileManager.default.fileExists(atPath: legacy.path) else { return }
        try? FileManager.default.copyItem(at: legacy, to: identityURL)
    }

    private static func refreshAvailability(_ shoot: ShootRecord, folderURL: URL) -> ShootRecord {
        var copy = shoot
        let folderExists = FileManager.default.fileExists(atPath: folderURL.path)
        if var raw = copy.rawFolder {
            raw.originalPath = folderURL.path
            raw.availability = folderExists ? .available : .missing
            raw.lastSeenAt = folderExists ? Date() : raw.lastSeenAt
            if raw.bookmarkData == nil {
                raw.bookmarkData = SecurityScopedAccess.bookmark(for: folderURL)
            }
            copy.rawFolder = raw
        }
        copy.assets = copy.assets.map { asset in
            var a = asset
            if folderExists {
                let path: String
                if !asset.source.relativePath.isEmpty {
                    path = folderURL.appendingPathComponent(asset.source.relativePath).path
                } else {
                    path = asset.source.originalPath
                }
                if FileManager.default.fileExists(atPath: path) {
                    a.source.originalPath = path
                    a.source.availability = .available
                    a.source.lastSeenAt = Date()
                } else if FileManager.default.fileExists(atPath: asset.source.originalPath) {
                    a.source.availability = .available
                } else {
                    a.source.availability = .missing
                }
            } else {
                a.source.availability = .missing
            }
            return a
        }
        return copy
    }
}
