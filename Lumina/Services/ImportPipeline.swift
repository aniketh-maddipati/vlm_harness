import Foundation
import ImageIO
import CoreGraphics

/// Progressive import — emits photos after thumbs, then refines scores live.
enum ImportPipeline {
    private static let previewConcurrency = 6
    /// Background thumb refine must stay out of the way of Meet/Pick/Decide.
    private static let refineConcurrency = 2
    private static var instantPreviewConcurrency: Int {
        min(max(ProcessInfo.processInfo.activeProcessorCount * 3, 16), 32)
    }
    private static var scoreConcurrency: Int {
        min(max(ProcessInfo.processInfo.activeProcessorCount, 8), 16)
    }

    /// UI pacing between major phases (skipped during instant preview burst).
    private static let phasePauseNs: UInt64 = 380_000_000

    static func importProject(
        sourceFolder: URL,
        photoURLs: [URL]? = nil,
        jpgFolder: URL?,
        keepRate: Double
    ) -> AsyncStream<ImportEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await runImport(
                        sourceFolder: sourceFolder,
                        photoURLs: photoURLs,
                        jpgFolder: jpgFolder,
                        keepRate: keepRate,
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

    static func importProject(
        rawFolder: URL,
        jpgFolder: URL?,
        keepRate: Double
    ) -> AsyncStream<ImportEvent> {
        importProject(sourceFolder: rawFolder, photoURLs: nil, jpgFolder: jpgFolder, keepRate: keepRate)
    }

    private static func runImport(
        sourceFolder: URL,
        photoURLs: [URL]?,
        jpgFolder: URL?,
        keepRate: Double,
        continuation: AsyncStream<ImportEvent>.Continuation
    ) async throws {
        let projectName = sourceFolder.lastPathComponent
        let thumbDir = try ProjectStore.cacheDirectory(for: projectName, tier: "thumbs")
        let gridDir = try ProjectStore.cacheDirectory(for: projectName, tier: "grid512")
        let proxyDir = try ProjectStore.cacheDirectory(for: projectName, tier: "proxy2048")

        let mediaFiles: [URL]
        if let photoURLs, !photoURLs.isEmpty {
            mediaFiles = photoURLs.filter(MediaFormats.isImportable)
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } else {
            mediaFiles = MediaFormats.collectPhotos(from: [sourceFolder])
        }

        guard !mediaFiles.isEmpty else { throw ImportError.noPhotos }

        let totalPhotos = mediaFiles.count
        var recentThumbs: [String] = []

        func emit(
            _ phase: ImportPhase,
            detail: String,
            completed: Int,
            total: Int,
            fraction: Double
        ) {
            let progress = ImportProgress(
                phase: phase,
                detail: detail,
                completed: completed,
                total: total,
                overallFraction: min(max(fraction, 0), 1),
                recentThumbPaths: recentThumbs
            )
            continuation.yield(.progress(progress))
            continuation.yield(.status(detail))
        }

        emit(.metadata, detail: "Opening photos…", completed: 0, total: totalPhotos, fraction: 0.02)

        // Narrative path: don't block first paint on exiftool — merge dates later.
        async let datesTask = Task.detached(priority: .utility) {
            ExifToolService.batchCaptureDates(
                in: sourceFolder,
                extensions: MediaFormats.exiftoolExtensions,
                files: photoURLs
            )
        }.value

        var profile = DevelopRecipe.neutral
        var tasteEntries: [TasteEntry] = []
        // Taste scan runs AFTER cull opens — never blocks first scroll.
        let deferredTasteFolder = jpgFolder

        emit(.previews, detail: "Loading previews…", completed: 0, total: totalPhotos, fraction: 0.08)

        // Tier 0: embedded JPEG only → scrollable in seconds
        var records = try await extractInstantPreviews(
            rawFiles: mediaFiles,
            dates: [:],
            gridDir: gridDir
        ) { done, total, thumbPath, partial in
            if let thumbPath { recentThumbs.append(thumbPath) }
            if recentThumbs.count > 32 { recentThumbs.removeFirst(recentThumbs.count - 32) }
            let frac = 0.08 + 0.40 * (Double(done) / Double(max(total, 1)))
            emit(.previews, detail: "Preview \(done) of \(total)", completed: done, total: total, fraction: frac)
            if done % 4 == 0 || done == total {
                continuation.yield(.photosUpdated(partial))
            }
        }

        CullEngine.assignBursts(&records)
        CullEngine.assignBurstClusters(&records)

        emit(.quality, detail: "Scoring…", completed: 0, total: totalPhotos, fraction: 0.52)
        records = await scoreQuality(records) { done, total in
            let frac = 0.52 + 0.18 * (Double(done) / Double(max(total, 1)))
            emit(.quality, detail: "Quality \(done)/\(total)", completed: done, total: total, fraction: frac)
        }
        CullEngine.scoreAndTier(&records, keepRate: keepRate)
        CullEngine.assignConfidence(&records)

        // Merge capture dates if ready (non-blocking timeout feel — await briefly).
        let dates = await datesTask
        if !dates.isEmpty {
            for i in records.indices {
                let raw = records[i].rawPath
                let name = records[i].filename
                records[i].capturedAt = dates[raw] ?? dates[name] ?? records[i].capturedAt
            }
            CullEngine.assignBursts(&records)
            CullEngine.assignBurstClusters(&records)
        }

        continuation.yield(.photosReady(records, profile: profile))

        var project = LuminaProject(
            name: projectName,
            rawFolder: sourceFolder.path,
            jpgFolder: jpgFolder?.path,
            keepRateTarget: keepRate,
            profile: profile,
            tasteSourceCount: 0,
            photos: records
        )
        project.collections = ExportService.draftCollections(from: records)
        try ProjectStore.save(project)

        let uncertain = records.filter(\.isUncertain).count
        emit(.ready, detail: "\(records.count) photos · \(uncertain) need you", completed: records.count, total: records.count, fraction: 0.72)
        // OPEN UI NOW — Narrative-style. Everything below refines in background.
        continuation.yield(.finished(project))

        // —— Background refinement (UI already interactive) ——
        emit(.previews, detail: "Building high-res…", completed: 0, total: totalPhotos, fraction: 0.74)
        records = await refineTiersInBackground(
            records: records,
            thumbDir: thumbDir,
            proxyDir: proxyDir
        ) { partial in
            continuation.yield(.photosUpdated(partial))
        }

        if let deferredTasteFolder {
            emit(.taste, detail: "Learning your look…", completed: 0, total: totalPhotos, fraction: 0.82)
            let built = await Task.detached(priority: .utility) {
                XMPDevelopParser.buildTasteLibrary(from: deferredTasteFolder)
            }.value
            profile = built.mean
            tasteEntries = built.entries
            try? TasteIndex.save(entries: tasteEntries, project: projectName)
        }

        // Stage cluster-changing work — do not push into the live session mid-Meet/Pick/Decide.
        var staged = records
        emit(.grouping, detail: "Grouping similar…", completed: 0, total: totalPhotos, fraction: 0.86)
        staged = await EmbeddingService.embedAndCluster(staged)
        CullEngine.scoreAndTier(&staged, keepRate: keepRate)

        let faceCandidates = staged.indices.filter {
            staged[$0].sharpness >= 0.15 && staged[$0].tier != .reject
        }
        emit(.faces, detail: "Faces…", completed: 0, total: faceCandidates.count, fraction: 0.92)
        await detectFaces(records: &staged, candidates: faceCandidates) { done, total in
            let frac = 0.92 + 0.04 * (Double(done) / Double(max(total, 1)))
            emit(.faces, detail: "Faces \(done)/\(total)", completed: done, total: total, fraction: frac)
        }

        emit(.edits, detail: "Matching look…", completed: 0, total: totalPhotos, fraction: 0.96)
        let entries = tasteEntries.isEmpty
            ? (try? TasteIndex.load(project: projectName)) ?? []
            : tasteEntries
        TasteRetriever.applyRecipes(to: &staged, library: entries, baseline: profile)
        CullEngine.assignConfidence(&staged)

        project.profile = profile
        project.tasteSourceCount = tasteEntries.count
        // Persist staged refinement to disk; UI applies at a session boundary.
        var stagedProject = project
        stagedProject.photos = staged
        stagedProject.collections = ExportService.draftCollections(from: staged)
        try ProjectStore.save(stagedProject)
        continuation.yield(.refinementReady(staged))
        emit(.ready, detail: "Refined · \(staged.count) photos", completed: staged.count, total: staged.count, fraction: 1.0)
        continuation.finish()
    }

    // MARK: - Extract

    /// Tier 0 — camera embedded JPEG (or one-time synth) so browse never demosaics.
    private static func extractInstantPreviews(
        rawFiles: [URL],
        dates: [String: Date],
        gridDir: URL,
        progress: @Sendable (Int, Int, String?, [PhotoRecord]) async -> Void
    ) async throws -> [PhotoRecord] {
        var records: [PhotoRecord?] = Array(repeating: nil, count: rawFiles.count)
        var done = 0
        let total = rawFiles.count
        let indexed = Array(rawFiles.enumerated())
        // Full browse previews live next to grid thumbs.
        let previewDir = gridDir.deletingLastPathComponent().appendingPathComponent("preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)

        for chunk in indexed.chunked(into: instantPreviewConcurrency) {
            try await withThrowingTaskGroup(of: (Int, PhotoRecord).self) { group in
                for (index, rawURL) in chunk {
                    group.addTask {
                        let stem = rawURL.deletingPathExtension().lastPathComponent
                        let previewURL = previewDir.appendingPathComponent(stem + ".jpg")
                        let gridURL = gridDir.appendingPathComponent(stem + ".jpg")

                        let extracted = PreviewExtractor.extractBrowsePreview(
                            to: previewURL,
                            from: rawURL,
                            maxPixelSize: 2400,
                            minLongEdge: 2000
                        )
                        if extracted.success, !FileManager.default.fileExists(atPath: gridURL.path) {
                            _ = PreviewExtractor.downscaleJPEG(from: previewURL, to: gridURL, maxPixelSize: 768)
                        }

                        let filename = rawURL.lastPathComponent
                        let capturedAt = dates[rawURL.path] ?? dates[filename]
                        let hasPreview = FileManager.default.fileExists(atPath: previewURL.path)
                        let hasGrid = FileManager.default.fileExists(atPath: gridURL.path)
                        let record = PhotoRecord(
                            rawPath: rawURL.path,
                            filename: filename,
                            thumbPath: hasPreview ? previewURL.path : (hasGrid ? gridURL.path : nil),
                            gridThumbPath: hasGrid ? gridURL.path : (hasPreview ? previewURL.path : nil),
                            proxyPath: nil,
                            previewOrigin: extracted.origin,
                            previewLongEdge: extracted.longEdge,
                            capturedAt: capturedAt
                        )
                        return (index, record)
                    }
                }
                for try await (index, record) in group {
                    records[index] = record
                    done += 1
                    let partial = records.compactMap { $0 }
                    await progress(done, total, record.gridThumbPath ?? record.thumbPath, partial)
                }
            }
        }
        return records.compactMap { $0 }
    }

    /// Tier 2 — high-res thumbs only (utility priority). Proxies deferred until Decide/export needs them.
    private static func refineTiersInBackground(
        records input: [PhotoRecord],
        thumbDir: URL,
        proxyDir: URL,
        onUpdate: @Sendable ([PhotoRecord]) async -> Void
    ) async -> [PhotoRecord] {
        var records = input
        let indices = Array(records.indices)
        // proxyDir kept in signature for call sites; 4096px proxy is lazy via DevelopEngine.ensureProxy.
        _ = proxyDir

        for chunk in indices.chunked(into: refineConcurrency) {
            await withTaskGroup(of: (Int, String?).self) { group in
                for index in chunk {
                    let rawPath = records[index].rawPath
                    group.addTask {
                        await Task.detached(priority: .utility) {
                            let rawURL = URL(fileURLWithPath: rawPath)
                            let stem = rawURL.deletingPathExtension().lastPathComponent
                            let thumbURL = thumbDir.appendingPathComponent(stem + ".jpg")

                            if !FileManager.default.fileExists(atPath: thumbURL.path) {
                                try? PreviewExtractor.extractBest(to: thumbURL, from: rawURL, maxPixelSize: 2048)
                            }
                            // Never point a record at a failed extraction.
                            guard FileManager.default.fileExists(atPath: thumbURL.path) else {
                                return (index, nil as String?)
                            }
                            return (index, thumbURL.path)
                        }.value
                    }
                }
                for await (index, thumbPath) in group {
                    if let thumbPath {
                        records[index].thumbPath = thumbPath
                    }
                }
            }
            await onUpdate(records)
        }
        return records
    }

    private static func extractAllTiers(
        rawFiles: [URL],
        dates: [String: Date],
        thumbDir: URL,
        gridDir: URL,
        proxyDir: URL,
        progress: @Sendable (Int, Int, String?, [PhotoRecord]) async -> Void
    ) async throws -> [PhotoRecord] {
        var records: [PhotoRecord?] = Array(repeating: nil, count: rawFiles.count)
        var done = 0
        let total = rawFiles.count
        let indexed = Array(rawFiles.enumerated())

        for chunk in indexed.chunked(into: previewConcurrency) {
            try await withThrowingTaskGroup(of: (Int, PhotoRecord).self) { group in
                for (index, rawURL) in chunk {
                    group.addTask {
                        let stem = rawURL.deletingPathExtension().lastPathComponent
                        let thumbURL = thumbDir.appendingPathComponent(stem + ".jpg")
                        let gridURL = gridDir.appendingPathComponent(stem + ".jpg")
                        let proxyURL = proxyDir.appendingPathComponent(stem + ".jpg")

                        if !FileManager.default.fileExists(atPath: thumbURL.path) {
                            try PreviewExtractor.extractBest(to: thumbURL, from: rawURL, maxPixelSize: 2048)
                        }
                        if !FileManager.default.fileExists(atPath: gridURL.path) {
                            if !PreviewExtractor.downscaleJPEG(from: thumbURL, to: gridURL, maxPixelSize: 1024) {
                                try PreviewExtractor.extractBest(to: gridURL, from: rawURL, maxPixelSize: 1024)
                            }
                        }
                        var proxyPath: String?
                        let ext = rawURL.pathExtension.uppercased()
                        let isProcessed = ["JPG", "JPEG", "JPE", "HEIC", "HEIF"].contains(ext)
                        let proxyMax = isProcessed ? 6000 : 4096
                        if !FileManager.default.fileExists(atPath: proxyURL.path) {
                            if PreviewExtractor.downscaleJPEG(from: thumbURL, to: proxyURL, maxPixelSize: proxyMax)
                                || ((try? PreviewExtractor.extractBest(to: proxyURL, from: rawURL, maxPixelSize: proxyMax)) != nil) {
                                proxyPath = proxyURL.path
                            } else if isProcessed, FileManager.default.fileExists(atPath: rawURL.path) {
                                // Keep full-res processed originals as proxy when decode matches source quality
                                proxyPath = rawURL.path
                            }
                        } else {
                            proxyPath = proxyURL.path
                        }

                        let filename = rawURL.lastPathComponent
                        let capturedAt = dates[rawURL.path] ?? dates[filename]
                        let record = PhotoRecord(
                            rawPath: rawURL.path,
                            filename: filename,
                            thumbPath: thumbURL.path,
                            gridThumbPath: gridURL.path,
                            proxyPath: proxyPath,
                            capturedAt: capturedAt
                        )
                        return (index, record)
                    }
                }
                for try await (index, record) in group {
                    records[index] = record
                    done += 1
                    let partial = records.compactMap { $0 }
                    await progress(done, total, record.thumbPath ?? record.gridThumbPath, partial)
                    // Tiny breath between UI updates so strip animates smoothly
                    if done % 2 == 0 {
                        try? await Task.sleep(nanoseconds: 40_000_000)
                    }
                }
            }
        }
        return records.compactMap { $0 }
    }

    private static func scoreQuality(
        _ input: [PhotoRecord],
        progress: @Sendable (Int, Int) async -> Void
    ) async -> [PhotoRecord] {
        var records = input
        let total = records.count
        guard total > 0 else { return records }

        let paths: [(Int, URL)] = records.indices.compactMap { index in
            guard let path = records[index].displayThumbPath else { return nil }
            return (index, URL(fileURLWithPath: path))
        }
        let concurrency = scoreConcurrency
        var done = 0

        for chunk in paths.chunked(into: concurrency) {
            await withTaskGroup(of: (Int, PhotoScorer.Result).self) { group in
                for (index, url) in chunk {
                    group.addTask {
                        (index, PhotoScorer.score(imageURL: url))
                    }
                }
                for await (index, scored) in group {
                    records[index].sharpness = scored.sharpness
                    records[index].exposureHealth = scored.exposure
                    records[index].aesthetic = scored.aesthetic
                    done += 1
                }
            }
            await progress(done, total)
        }
        return records
    }

    private static func detectFaces(
        records: inout [PhotoRecord],
        candidates: [Int],
        progress: @Sendable (Int, Int) async -> Void
    ) async {
        var done = 0
        let total = candidates.count
        let paths = Dictionary(uniqueKeysWithValues: candidates.compactMap { i -> (Int, String)? in
            guard let p = records[i].displayThumbPath else { return nil }
            return (i, p)
        })

        for chunk in paths.keys.sorted().chunked(into: 4) {
            await withTaskGroup(of: (Int, Bool, Double).self) { group in
                for index in chunk {
                    guard let path = paths[index] else { continue }
                    group.addTask {
                        let url = URL(fileURLWithPath: path)
                        let result = FaceDetector.analyze(url)
                        return (index, result.hasFace, result.quality)
                    }
                }
                for await (index, hasFace, quality) in group {
                    records[index].faceDetected = hasFace
                    records[index].faceQuality = quality
                    done += 1
                }
            }
            await progress(done, total)
            // No artificial sleep — Narrative never pauses for UX chrome during AI.
        }
    }

    // MARK: - L1 catalog index (fast backlog pass)

    /// Thumbs + quality + burst sets — skips embeddings, faces, and taste for speed.
    static func indexLightweight(
        sourceFolder: URL,
        projectName: String,
        keepRate: Double
    ) async throws -> LuminaProject {
        let thumbDir = try ProjectStore.cacheDirectory(for: projectName, tier: "thumbs")
        let gridDir = try ProjectStore.cacheDirectory(for: projectName, tier: "grid512")

        let mediaFiles = MediaFormats.collectPhotos(from: [sourceFolder])
        guard !mediaFiles.isEmpty else { throw ImportError.noPhotos }

        let dates = await Task.detached(priority: .utility) {
            ExifToolService.batchCaptureDates(
                in: sourceFolder,
                extensions: MediaFormats.exiftoolExtensions,
                files: nil
            )
        }.value

        var records = try await extractInstantPreviews(
            rawFiles: mediaFiles,
            dates: dates,
            gridDir: gridDir
        ) { _, _, _, _ in }

        CullEngine.assignBursts(&records)
        records = await scoreQuality(records) { _, _ in }
        CullEngine.scoreAndTier(&records, keepRate: keepRate)
        CullEngine.assignBurstClusters(&records)
        CullEngine.assignConfidence(&records)

        var project = LuminaProject(
            name: projectName,
            rawFolder: sourceFolder.path,
            keepRateTarget: keepRate,
            profile: .neutral,
            photos: records
        )
        project.collections = ExportService.draftCollections(from: records)
        try ProjectStore.save(project)
        return project
    }
}

enum ImportError: LocalizedError {
    case noPhotos
    var errorDescription: String? {
        switch self {
        case .noPhotos: "No importable photos found. Try JPG, HEIC, PNG, TIFF, or camera RAW."
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
