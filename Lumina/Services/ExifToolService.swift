import Foundation

nonisolated enum ExifToolService {
    /// Homebrew on Apple silicon installs here; Intel Homebrew and Linux apt use the others.
    private static let candidatePaths = [
        "/opt/homebrew/bin/exiftool",
        "/usr/local/bin/exiftool",
        "/usr/bin/exiftool",
    ]

    private static func resolvedPath() -> String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool {
        resolvedPath() != nil
    }

    static func extractPreview(from rawURL: URL, to destURL: URL) throws {
        let data = try runData(arguments: ["-b", "-PreviewImage", rawURL.path])
        guard !data.isEmpty else {
            throw ExifToolError.previewExtractionFailed(rawURL.lastPathComponent)
        }
        try data.write(to: destURL, options: .atomic)
    }

    static func batchCaptureDates(
        in folder: URL,
        extensions: [String] = MediaFormats.exiftoolExtensions,
        files: [URL]? = nil
    ) -> [String: Date] {
        guard isAvailable else { return fileModificationDates(files: files, folder: folder) }
        var args = ["-DateTimeOriginal", "-CreateDate", "-json", "-q", "-q"]
        if let files, !files.isEmpty {
            args.append(contentsOf: files.map(\.path))
        } else {
            for ext in extensions {
                args.append("-ext")
                args.append(ext)
            }
            args.append(folder.path)
        }

        // Read stdout regardless of exit status. exiftool exits 1 when *any* input is
        // unreadable, having already written perfectly good JSON for every other file —
        // so one zero-byte stub on a card used to throw away the capture dates of the
        // entire shoot. Measured on a 381-frame folder holding one empty ARW: 58 KB of
        // valid JSON, exit 1, and a chronology rebuilt from file copy times (42 chapters
        // instead of 35). Status is therefore not a reason to discard output; only
        // unparseable output is.
        guard let data = runDataIgnoringStatus(arguments: args),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return fileModificationDates(files: files, folder: folder)
        }

        var result: [String: Date] = [:]
        for item in json {
            guard let source = item["SourceFile"] as? String else { continue }
            let raw = (item["DateTimeOriginal"] as? String) ?? (item["CreateDate"] as? String)
            guard let raw, let date = parseExifDate(raw) else { continue }
            result[source] = date
            result[URL(fileURLWithPath: source).lastPathComponent] = date
        }
        if result.isEmpty {
            return fileModificationDates(files: files, folder: folder)
        }

        // Backfill only the files exiftool could not date. The fallback is per file,
        // never per shoot: a frame with no readable EXIF still gets its modification
        // time, and its neighbours keep the time the shutter actually fired. An
        // EXIF-derived entry is never overwritten.
        if let files {
            for url in files where result[url.path] == nil {
                guard let mtime = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate else { continue }
                result[url.path] = mtime
                if result[url.lastPathComponent] == nil {
                    result[url.lastPathComponent] = mtime
                }
            }
        }
        return result
    }

    /// stdout of `exiftool`, keeping it even when the process exits non-zero.
    ///
    /// `runData` throws on a non-zero status, which is right for `-b -PreviewImage`
    /// (a failed extraction has no usable bytes) and wrong for `-json` over a batch
    /// (one bad input does not invalidate the rest). Returns nil only when the tool
    /// could not be launched at all.
    private static func runDataIgnoringStatus(arguments: [String]) -> Data? {
        guard let exifToolPath = resolvedPath() else { return nil }
        guard let (data, _) = try? captureOutput(
            executable: URL(fileURLWithPath: exifToolPath),
            arguments: arguments
        ) else { return nil }
        return data.isEmpty ? nil : data
    }

    private static func fileModificationDates(files: [URL]?, folder: URL) -> [String: Date] {
        let urls = files ?? MediaFormats.collectPhotos(from: [folder])
        var result: [String: Date] = [:]
        for url in urls {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            result[url.path] = date
            result[url.lastPathComponent] = date
        }
        return result
    }

    static func buildProfile(from jpgFolder: URL) -> DevelopRecipe {
        XMPDevelopParser.buildTasteLibrary(from: jpgFolder).mean
    }

    static func runDataPublic(arguments: [String]) throws -> Data {
        try runData(arguments: arguments)
    }

    private static func runData(arguments: [String]) throws -> Data {
        guard let exifToolPath = resolvedPath() else { throw ExifToolError.notInstalled }
        let (data, status) = try captureOutput(
            executable: URL(fileURLWithPath: exifToolPath),
            arguments: arguments
        )
        guard status == 0 else {
            throw ExifToolError.commandFailed(arguments.joined(separator: " "))
        }
        return data
    }

    /// Run `executable` and return everything it wrote to stdout.
    ///
    /// stdout is drained **before** waiting for exit. A pipe holds 64 KB; a
    /// child that writes more blocks until someone reads, and a parent that is
    /// waiting for exit first never does. An embedded preview (~600 KB) is
    /// always past that line, and `-json` over a few hundred frames is too —
    /// which is how preview extraction hung instead of returning a photograph,
    /// and how "Reading dates…" hung for good on any shoot larger than a small
    /// card. stderr goes to the null device rather than into a second pipe that
    /// nothing drains, so it can never fill and block the writer either.
    static func captureOutput(
        executable: URL,
        arguments: [String]
    ) throws -> (data: Data, status: Int32) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (data, process.terminationStatus)
    }

    private static func parseExifDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let date = formatter.date(from: string) { return date }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)
    }
}

enum ExifToolError: LocalizedError {
    case previewExtractionFailed(String)
    case notInstalled
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .previewExtractionFailed(let name):
            "Could not extract preview from \(name)"
        case .notInstalled:
            "exiftool not found — install with brew install exiftool"
        case .commandFailed(let cmd):
            "exiftool failed: \(cmd)"
        }
    }
}
