import Foundation

enum ExifToolService {
    private static let exifToolPath = "/usr/local/bin/exiftool"

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: exifToolPath)
    }

    // MARK: - Single file (fallback)

    static func extractPreview(from rawURL: URL, to destURL: URL) throws {
        let data = try runData(arguments: ["-b", "-PreviewImage", rawURL.path])
        guard !data.isEmpty else {
            throw ExifToolError.previewExtractionFailed(rawURL.lastPathComponent)
        }
        try data.write(to: destURL, options: .atomic)
    }

    // MARK: - Batch operations (one process for whole folder)

    /// One exiftool call for all capture dates in a folder.
    static func batchCaptureDates(in folder: URL, extensions: [String] = ["ARW"]) -> [String: Date] {
        guard isAvailable else { return [:] }
        var args = ["-DateTimeOriginal", "-json", "-q", "-q"]
        for ext in extensions {
            args.append("-ext")
            args.append(ext)
        }
        args.append(folder.path)

        guard let data = try? runData(arguments: args),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }

        var result: [String: Date] = [:]
        for item in json {
            guard let source = item["SourceFile"] as? String,
                  let raw = item["DateTimeOriginal"] as? String,
                  let date = parseExifDate(raw) else { continue }
            result[source] = date
            result[URL(fileURLWithPath: source).lastPathComponent] = date
        }
        return result
    }

    /// One exiftool call for taste profile from all JPGs.
    static func buildProfile(from jpgFolder: URL) -> DevelopProfile {
        guard isAvailable else { return DevelopProfile() }

        var args = [
            "-json", "-q", "-q",
            "-XMP-crs:Exposure2012",
            "-XMP-crs:ColorTemperature",
            "-XMP-crs:Contrast2012",
            "-XMP-crs:Highlights2012",
            "-XMP-crs:Shadows2012",
            "-XMP-crs:Vibrance",
            "-ext", "jpg",
            "-ext", "jpeg",
            jpgFolder.path,
        ]

        guard let data = try? runData(arguments: args),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !json.isEmpty else {
            return DevelopProfile()
        }

        var exposures: [Double] = []
        var temps: [Double] = []
        var contrasts: [Double] = []
        var highlights: [Double] = []
        var shadows: [Double] = []
        var vibrances: [Double] = []

        for item in json {
            if let v = parseDouble(item["Exposure2012"]) { exposures.append(v) }
            if let v = parseDouble(item["ColorTemperature"]) { temps.append(v) }
            if let v = parseDouble(item["Contrast2012"]) { contrasts.append(v) }
            if let v = parseDouble(item["Highlights2012"]) { highlights.append(v) }
            if let v = parseDouble(item["Shadows2012"]) { shadows.append(v) }
            if let v = parseDouble(item["Vibrance"]) { vibrances.append(v) }
        }

        return DevelopProfile(
            exposure: mean(exposures),
            temperature: mean(temps, default: 6500),
            contrast: mean(contrasts),
            highlights: mean(highlights),
            shadows: mean(shadows),
            vibrance: mean(vibrances),
            sourceCount: json.count
        )
    }

    // MARK: - Process runner

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

    private static func parseDouble(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "+", with: "")
            return Double(cleaned)
        }
        return nil
    }

    private static func mean(_ values: [Double], default defaultValue: Double = 0) -> Double {
        guard !values.isEmpty else { return defaultValue }
        return values.reduce(0, +) / Double(values.count)
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
