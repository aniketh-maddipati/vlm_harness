import Foundation

enum ProjectStore {
    static func supportDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumina", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func cacheDirectory(for projectName: String) throws -> URL {
        let dir = try supportDirectory()
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectName, isDirectory: true)
            .appendingPathComponent("cache/thumbs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ project: LuminaProject) throws {
        let dir = try supportDirectory().appendingPathComponent("projects/\(project.name)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("project.json")
        let data = try JSONEncoder.pretty.encode(project)
        try data.write(to: url, options: .atomic)
    }
}

/// Parallel import with phased scoring — blur first, faces only on survivors.
enum ImportPipeline {
    private static let previewConcurrency = 8
    private static let scoreConcurrency = 8
    private static let faceConcurrency = 4
    /// Skip expensive Vision on obvious rejects.
    private static let faceSharpnessThreshold = 0.15

    static func importProject(
        rawFolder: URL,
        jpgFolder: URL?,
        keepRate: Double,
        progress: @Sendable (String) async -> Void
    ) async throws -> LuminaProject {
        let projectName = rawFolder.lastPathComponent
        let cacheDir = try ProjectStore.cacheDirectory(for: projectName)

        await progress("Reading metadata…")
        let dates = await Task.detached(priority: .userInitiated) {
            ExifToolService.batchCaptureDates(in: rawFolder)
        }.value

        let profile: DevelopProfile
        if let jpgFolder {
            profile = await Task.detached(priority: .userInitiated) {
                ExifToolService.buildProfile(from: jpgFolder)
            }.value
        } else {
            profile = DevelopProfile()
        }

        let rawFiles = try FileManager.default.contentsOfDirectory(at: rawFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.uppercased() == "ARW" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !rawFiles.isEmpty else { throw ImportError.noRAWFiles }

        // Phase 1 — parallel preview extract (ImageIO, no subprocess per file)
        await progress("Extracting previews 0/\(rawFiles.count)…")
        let thumbPaths = try await extractPreviews(rawFiles: rawFiles, cacheDir: cacheDir) { done, total in
            await progress("Extracting previews \(done)/\(total)…")
        }

        // Phase 2 — parallel blur scoring (cheap, downsampled)
        await progress("Scoring sharpness 0/\(rawFiles.count)…")
        var records = try await scoreSharpness(rawFiles: rawFiles, thumbPaths: thumbPaths, dates: dates) { done, total in
            await progress("Scoring sharpness \(done)/\(total)…")
        }

        // Phase 3 — face detect only on non-obvious rejects (~40-60% of files)
        let faceCandidates = records.enumerated().filter { $0.element.sharpness >= faceSharpnessThreshold }
        await progress("Detecting faces 0/\(faceCandidates.count)…")
        await detectFaces(records: &records, candidates: faceCandidates.map { $0.offset }) { done, total in
            await progress("Detecting faces \(done)/\(total)…")
        }

        await progress("Grouping bursts and ranking…")
        CullEngine.assignBursts(&records)
        CullEngine.scoreAndTier(&records, keepRate: keepRate)

        let project = LuminaProject(
            name: projectName,
            rawFolder: rawFolder.path,
            jpgFolder: jpgFolder?.path,
            keepRateTarget: keepRate,
            profile: profile,
            photos: records
        )

        try ProjectStore.save(project)
        return project
    }

    // MARK: - Phase 1

    private static func extractPreviews(
        rawFiles: [URL],
        cacheDir: URL,
        progress: @Sendable (Int, Int) async -> Void
    ) async throws -> [String: String] {
        var thumbPaths: [String: String] = [:]
        let total = rawFiles.count
        var done = 0

        for chunk in rawFiles.chunked(into: previewConcurrency) {
            try await withThrowingTaskGroup(of: (String, String).self) { group in
                for rawURL in chunk {
                    group.addTask {
                        let key = rawURL.lastPathComponent
                        let thumbURL = cacheDir.appendingPathComponent(rawURL.deletingPathExtension().lastPathComponent + ".jpg")
                        if !FileManager.default.fileExists(atPath: thumbURL.path) {
                            try PreviewExtractor.extract(to: thumbURL, from: rawURL)
                        }
                        return (key, thumbURL.path)
                    }
                }
                for try await (key, path) in group {
                    thumbPaths[key] = path
                    done += 1
                }
            }
            await progress(done, total)
        }

        return thumbPaths
    }

    // MARK: - Phase 2

    private static func scoreSharpness(
        rawFiles: [URL],
        thumbPaths: [String: String],
        dates: [String: Date],
        progress: @Sendable (Int, Int) async -> Void
    ) async throws -> [PhotoRecord] {
        var records: [PhotoRecord?] = Array(repeating: nil, count: rawFiles.count)
        var done = 0
        let total = rawFiles.count

        let indexed = Array(rawFiles.enumerated())
        for chunk in indexed.chunked(into: scoreConcurrency) {
            await withTaskGroup(of: (Int, PhotoRecord).self) { group in
                for (index, rawURL) in chunk {
                    group.addTask {
                        let filename = rawURL.lastPathComponent
                        let thumbPath = thumbPaths[filename]
                        let sharpness: Double
                        if let thumbPath {
                            sharpness = BlurScorer.score(imageURL: URL(fileURLWithPath: thumbPath))
                        } else {
                            sharpness = 0
                        }
                        let capturedAt = dates[rawURL.path] ?? dates[filename]
                        let record = PhotoRecord(
                            rawPath: rawURL.path,
                            filename: filename,
                            thumbPath: thumbPath,
                            capturedAt: capturedAt,
                            sharpness: sharpness,
                            faceDetected: false
                        )
                        return (index, record)
                    }
                }
                for await (index, record) in group {
                    records[index] = record
                    done += 1
                }
            }
            await progress(done, total)
        }

        return records.compactMap { $0 }
    }

    // MARK: - Phase 3

    private static func detectFaces(
        records: inout [PhotoRecord],
        candidates: [Int],
        progress: @Sendable (Int, Int) async -> Void
    ) async {
        var done = 0
        let total = candidates.count
        let thumbByIndex = Dictionary(uniqueKeysWithValues: candidates.compactMap { index -> (Int, String)? in
            guard let path = records[index].thumbPath else { return nil }
            return (index, path)
        })

        for chunk in thumbByIndex.keys.sorted().chunked(into: faceConcurrency) {
            await withTaskGroup(of: (Int, Bool).self) { group in
                for index in chunk {
                    guard let thumbPath = thumbByIndex[index] else { continue }
                    group.addTask {
                        let hasFace = FaceDetector.hasFace(in: URL(fileURLWithPath: thumbPath))
                        return (index, hasFace)
                    }
                }
                for await (index, hasFace) in group {
                    records[index].faceDetected = hasFace
                    done += 1
                }
            }
            await progress(done, total)
        }
    }
}

enum ImportError: LocalizedError {
    case noRAWFiles

    var errorDescription: String? {
        switch self {
        case .noRAWFiles: "No .ARW files found in the selected folder."
        }
    }
}

// MARK: - Chunk helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count / size) + 1)
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
