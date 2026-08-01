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

enum ImportPipeline {
    static func importProject(
        rawFolder: URL,
        jpgFolder: URL?,
        keepRate: Double,
        progress: @Sendable (String) async -> Void
    ) async throws -> LuminaProject {
        let projectName = rawFolder.lastPathComponent
        let cacheDir = try ProjectStore.cacheDirectory(for: projectName)

        var profile = DevelopProfile()
        if let jpgFolder {
            await progress("Reading Lightroom XMP profile…")
            profile = ExifToolService.buildProfile(from: jpgFolder)
        }

        let rawFiles = try FileManager.default.contentsOfDirectory(at: rawFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.uppercased() == "ARW" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !rawFiles.isEmpty else {
            throw ImportError.noRAWFiles
        }

        var photos: [PhotoRecord] = []
        photos.reserveCapacity(rawFiles.count)

        for (index, rawURL) in rawFiles.enumerated() {
            await progress("Importing \(index + 1)/\(rawFiles.count)…")

            let thumbURL = cacheDir.appendingPathComponent(rawURL.deletingPathExtension().lastPathComponent + ".jpg")
            if !FileManager.default.fileExists(atPath: thumbURL.path) {
                try ExifToolService.extractPreview(from: rawURL, to: thumbURL)
            }

            let capturedAt = ExifToolService.captureDate(for: rawURL) ?? ExifToolService.captureDate(for: thumbURL)
            let sharpness = BlurScorer.score(imageURL: thumbURL)
            let faceDetected = FaceDetector.hasFace(in: thumbURL)

            photos.append(PhotoRecord(
                rawPath: rawURL.path,
                filename: rawURL.lastPathComponent,
                thumbPath: thumbURL.path,
                capturedAt: capturedAt,
                sharpness: sharpness,
                faceDetected: faceDetected
            ))
        }

        await progress("Grouping bursts and ranking…")
        CullEngine.assignBursts(&photos)
        CullEngine.scoreAndTier(&photos, keepRate: keepRate)

        let project = LuminaProject(
            name: projectName,
            rawFolder: rawFolder.path,
            jpgFolder: jpgFolder?.path,
            keepRateTarget: keepRate,
            profile: profile,
            photos: photos
        )

        try ProjectStore.save(project)
        return project
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

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
