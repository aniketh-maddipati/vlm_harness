// SALVAGE(D40) — salvaged service, retained for a named capability only.
// Contract: design/contract-v6.md D40 (salvage: EmbeddingService grouping, ExifToolService).
// Allowed callers and denied entry points: Scripts/lint/quarantine_d40.sh.
import Foundation

nonisolated enum ExifToolService {
    private static let exifToolPath = "/usr/local/bin/exiftool"

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: exifToolPath)
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

        guard let data = try? runData(arguments: args),
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
        return result
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
        guard isAvailable else { throw ExifToolError.notInstalled }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw ExifToolError.commandFailed(arguments.joined(separator: " "))
        }
        return data
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
            "exiftool not found at /usr/local/bin/exiftool"
        case .commandFailed(let cmd):
            "exiftool failed: \(cmd)"
        }
    }
}
