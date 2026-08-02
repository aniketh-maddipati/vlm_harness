import Foundation
import ImageIO
import CoreGraphics

/// Progressive import — emits photos after thumbs, then refines scores live.
enum ImportPipeline {
    private static let previewConcurrency = 6
    private static let scoreConcurrency = 6

    /// Gentle pause so phase labels are readable (does not block heavy work).
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

        emit(.metadata, detail: "Reading capture dates…", completed: 0, total: totalPhotos, fraction: 0.02)

        async let datesTask = Task.detached(priority: .userInitiated) {
            ExifToolService.batchCaptureDates(
                in: sourceFolder,
                extensions: MediaFormats.exiftoolExtensions,
                files: photoURLs
            )
        }.value

        var profile = DevelopRecipe.neutral
        var tasteEntries: [TasteEntry] = []
        if let jpgFolder {
            emit(.taste, detail: "Scanning Lightroom edits…", completed: 0, total: totalPhotos, fraction: 0.06)
            let built = await Task.detached(priority: .userInitiated) {
                XMPDevelopParser.buildTasteLibrary(from: jpgFolder)
            }.value
            profile = built.mean
            tasteEntries = built.entries
            try? TasteIndex.save(entries: tasteEntries, project: projectName)
            emit(.taste, detail: "Learned from \(tasteEntries.count) edits", completed: tasteEntries.count, total: tasteEntries.count, fraction: 0.10)
            try? await Task.sleep(nanoseconds: phasePauseNs)
        }

        let dates = await datesTask

        emit(.previews, detail: "Extracting previews…", completed: 0, total: totalPhotos, fraction: 0.12)

        var records = try await extractAllTiers(
            rawFiles: mediaFiles,
            dates: dates,
            thumbDir: thumbDir,
            gridDir: gridDir,
            proxyDir: proxyDir
        ) { done, total, thumbPath, partial in
            if let thumbPath { recentThumbs.append(thumbPath) }
            if recentThumbs.count > 32 { recentThumbs.removeFirst(recentThumbs.count - 32) }
            let frac = 0.12 + 0.33 * (Double(done) / Double(max(total, 1)))
            emit(.previews, detail: "Preview \(done) of \(total)", completed: done, total: total, fraction: frac)
            if done % 3 == 0 || done == total {
                continuation.yield(.photosUpdated(partial))
            }
        }

        CullEngine.assignBursts(&records)
        continuation.yield(.photosReady(records, profile: profile))
        try? await Task.sleep(nanoseconds: phasePauseNs)

        emit(.quality, detail: "Scoring sharpness…", completed: 0, total: totalPhotos, fraction: 0.48)
        records = await scoreQuality(records) { done, total in
            let frac = 0.48 + 0.14 * (Double(done) / Double(max(total, 1)))
            emit(.quality, detail: "Quality \(done)/\(total)", completed: done, total: total, fraction: frac)
        }
        CullEngine.scoreAndTier(&records, keepRate: keepRate)
        continuation.yield(.photosUpdated(records))
        try? await Task.sleep(nanoseconds: phasePauseNs)

        emit(.grouping, detail: "Grouping similar shots…", completed: 0, total: totalPhotos, fraction: 0.64)
        records = await EmbeddingService.embedAndCluster(records)
        CullEngine.scoreAndTier(&records, keepRate: keepRate)
        let setCount = Set(records.compactMap(\.clusterID)).count
        emit(.grouping, detail: "Found \(setCount) sets", completed: setCount, total: setCount, fraction: 0.76)
        continuation.yield(.photosUpdated(records))
        try? await Task.sleep(nanoseconds: phasePauseNs)

        let faceCandidates = records.indices.filter {
            records[$0].sharpness >= 0.15 && records[$0].tier != .reject
        }
        emit(.faces, detail: "Checking faces…", completed: 0, total: faceCandidates.count, fraction: 0.78)
        await detectFaces(records: &records, candidates: faceCandidates) { done, total in
            let frac = 0.78 + 0.10 * (Double(done) / Double(max(total, 1)))
            emit(.faces, detail: "Faces \(done)/\(total)", completed: done, total: total, fraction: frac)
        }
        CullEngine.scoreAndTier(&records, keepRate: keepRate)
        continuation.yield(.photosUpdated(records))
        try? await Task.sleep(nanoseconds: phasePauseNs)

        emit(.edits, detail: "Matching your edit style…", completed: 0, total: totalPhotos, fraction: 0.90)
        let entries = tasteEntries.isEmpty
            ? (try? TasteIndex.load(project: projectName)) ?? []
            : tasteEntries
        TasteRetriever.applyRecipes(to: &records, library: entries, baseline: profile)
        CullEngine.assignConfidence(&records)
        continuation.yield(.photosUpdated(records))

        var project = LuminaProject(
            name: projectName,
            rawFolder: sourceFolder.path,
            jpgFolder: jpgFolder?.path,
            keepRateTarget: keepRate,
            profile: profile,
            tasteSourceCount: tasteEntries.count,
            photos: records
        )
        project.collections = ExportService.draftCollections(from: records)
        try ProjectStore.save(project)

        let uncertain = records.filter(\.isUncertain).count
        emit(.ready, detail: "\(records.count) photos · \(uncertain) may need you", completed: records.count, total: records.count, fraction: 1.0)
        try? await Task.sleep(nanoseconds: 450_000_000)
        continuation.yield(.finished(project))
        continuation.finish()
    }

    // MARK: - Extract

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
        var done = 0
        let total = records.count
        let indexed = Array(records.indices)

        for chunk in indexed.chunked(into: scoreConcurrency) {
            await withTaskGroup(of: (Int, Double, Double, Double).self) { group in
                for index in chunk {
                    group.addTask {
                        let path = records[index].displayThumbPath.flatMap { URL(fileURLWithPath: $0) }
                        let sharpness = path.map { BlurScorer.score(imageURL: $0) } ?? 0
                        let exposure = path.map { QualityScorer.exposureHealth(imageURL: $0) } ?? 0.5
                        let aesthetic = 0.45 + sharpness * 0.3 + exposure * 0.25
                        return (index, sharpness, exposure, min(max(aesthetic, 0), 1))
                    }
                }
                for await (index, sharpness, exposure, aesthetic) in group {
                    records[index].sharpness = sharpness
                    records[index].exposureHealth = exposure
                    records[index].aesthetic = aesthetic
                    done += 1
                }
            }
            await progress(done, total)
            try? await Task.sleep(nanoseconds: 30_000_000)
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
            try? await Task.sleep(nanoseconds: 30_000_000)
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

        var records = try await extractAllTiers(
            rawFiles: mediaFiles,
            dates: dates,
            thumbDir: thumbDir,
            gridDir: gridDir,
            proxyDir: gridDir
        ) { _, _, _, _ in }

        CullEngine.assignBursts(&records)
        records = await scoreQuality(records) { _, _ in }
        CullEngine.scoreAndTier(&records, keepRate: keepRate)
        CullEngine.assignBurstClusters(&records)
        CullEngine.assignConfidence(&records)

        var actions = PhotoAgentOrchestrator.autoResolveHighConfidence(
            in: &records,
            threshold: 0.85
        )
        _ = actions

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
