import Foundation

enum ExifToolService {
    private static let exifToolPath = "/usr/local/bin/exiftool"

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: exifToolPath)
    }

    static func extractPreview(from rawURL: URL, to destURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        process.arguments = ["-b", "-PreviewImage", rawURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExifToolError.previewExtractionFailed(rawURL.lastPathComponent)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            throw ExifToolError.previewExtractionFailed(rawURL.lastPathComponent)
        }
        try data.write(to: destURL, options: .atomic)
    }

    static func captureDate(for url: URL) -> Date? {
        let output = run(arguments: ["-s", "-s", "-s", "-DateTimeOriginal", url.path])
        guard let output, !output.isEmpty else { return nil }
        return parseExifDate(output)
    }

    static func buildProfile(from jpgFolder: URL) -> DevelopProfile {
        let jpgs = (try? FileManager.default.contentsOfDirectory(at: jpgFolder, includingPropertiesForKeys: nil))?
            .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) } ?? []

        var exposures: [Double] = []
        var temps: [Double] = []
        var contrasts: [Double] = []
        var highlights: [Double] = []
        var shadows: [Double] = []
        var vibrances: [Double] = []

        for jpg in jpgs {
            if let v = doubleTag("XMP-crs:Exposure2012", file: jpg) { exposures.append(v) }
            if let v = doubleTag("XMP-crs:ColorTemperature", file: jpg) { temps.append(v) }
            if let v = doubleTag("XMP-crs:Contrast2012", file: jpg) { contrasts.append(v) }
            if let v = doubleTag("XMP-crs:Highlights2012", file: jpg) { highlights.append(v) }
            if let v = doubleTag("XMP-crs:Shadows2012", file: jpg) { shadows.append(v) }
            if let v = doubleTag("XMP-crs:Vibrance", file: jpg) { vibrances.append(v) }
        }

        return DevelopProfile(
            exposure: mean(exposures),
            temperature: mean(temps, default: 6500),
            contrast: mean(contrasts),
            highlights: mean(highlights),
            shadows: mean(shadows),
            vibrance: mean(vibrances),
            sourceCount: jpgs.count
        )
    }

    private static func doubleTag(_ tag: String, file: URL) -> Double? {
        guard let raw = run(arguments: ["-s", "-s", "-s", "-\(tag)", file.path]) else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "+", with: "")
        return Double(cleaned)
    }

    private static func run(arguments: [String]) -> String? {
        guard isAvailable else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exifToolPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
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

    var errorDescription: String? {
        switch self {
        case .previewExtractionFailed(let name):
            "Could not extract preview from \(name)"
        case .notInstalled:
            "exiftool not found at /usr/local/bin/exiftool"
        }
    }
}
