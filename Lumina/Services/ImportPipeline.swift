import Foundation
import ImageIO
import CoreGraphics

/// Progressive import — emits photos after thumbs, then refines scores live.
enum ImportPipeline {
    private static let previewConcurrency = 8
    private static let scoreConcurrency = 8

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

    /// Back-compat alias.
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

        continuation.yield(.status("Reading metadata…"))
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
            continuation.yield(.status("Building taste index from Lightroom XMP…"))
            let built = await Task.detached(priority: .userInitiated) {
                XMPDevelopParser.buildTasteLibrary(from: jpgFolder)
            }.value
            profile = built.mean
            tasteEntries = built.entries
            try? TasteIndex.save(entries: tasteEntries, project: projectName)
        }

        let dates = await datesTask

        // Phase 1 — extract previews + grid thumbs; show UI ASAP
        continuation.yield(.status("Extracting previews 0/\(mediaFiles.count)…"))
        var records = try await extractAllTiers(
            rawFiles: mediaFiles,
            dates: dates,
            thumbDir: thumbDir,
            gridDir: gridDir,
            proxyDir: proxyDir
        ) { done, total in
            continuation.yield(.status("Extracting previews \(done)/\(total)…"))
        }

        CullEngine.assignBursts(&records)
        continuation.yield(.photosReady(records, profile: profile))

        // Phase 2 — sharpness + exposure (faces deferred)
        continuation.yield(.status("Scoring quality 0/\(mediaFiles.count)…"))
        records = await scoreQuality(records) { done, total in
            continuation.yield(.status("Scoring quality \(done)/\(total)…"))
        }
        CullEngine.scoreAndTier(&records, keepRate: keepRate)
        continuation.yield(.photosUpdated(records))

        // Phase 3 — embeddings + clusters
        continuation.yield(.status("Clustering by similarity…"))
        records = await EmbeddingService.embedAndCluster(records)
        CullEngine.scoreAndTier(&records, keepRate: keepRate)
        continuation.yield(.photosUpdated(records))

        // Phase 4 — deferred faces on survivors only
        let faceCandidates = records.indices.filter {
            records[$0].sharpness >= 0.15 && records[$0].tier != .reject
        }
        continuation.yield(.status("Detecting faces 0/\(faceCandidates.count)…"))
        await detectFaces(records: &records, candidates: faceCandidates) { done, total in
            continuation.yield(.status("Detecting faces \(done)/\(total)…"))
        }
        CullEngine.scoreAndTier(&records, keepRate: keepRate)
        continuation.yield(.photosUpdated(records))

        // Phase 5 — per-photo taste recipes
        continuation.yield(.status("Applying per-photo taste edits…"))
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
            photos: records
        )
        project.collections = ExportService.draftCollections(from: records)
        try ProjectStore.save(project)

        continuation.yield(.status("Ready · \(records.filter(\.isUncertain).count) need you"))
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
        progress: @Sendable (Int, Int) async -> Void
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
                            try PreviewExtractor.extract(to: thumbURL, from: rawURL, maxPixelSize: 1600)
                        }
                        if !FileManager.default.fileExists(atPath: gridURL.path) {
                            if !PreviewExtractor.downscaleJPEG(from: thumbURL, to: gridURL, maxPixelSize: 512) {
                                try PreviewExtractor.extract(to: gridURL, from: rawURL, maxPixelSize: 512)
                            }
                        }
                        // Proxy generated lazily on first develop; create light stub path pointer
                        let proxyPath: String? = FileManager.default.fileExists(atPath: proxyURL.path)
                            ? proxyURL.path : nil

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
                }
            }
            await progress(done, total)
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
        }
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
