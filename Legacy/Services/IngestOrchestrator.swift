// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import Foundation

/// Deep discovery, dedup, taste auto-detect, and ingest manifest for zero-click import.
enum IngestOrchestrator {
    private static let tasteSiblingNames = [
        "edited", "edit", "jpg", "jpeg", "export", "exports", "lightroom", "selects", "final",
    ]

    private static let cameraRootMarkers = [
        "dcim", "private", "m4root", "nikon", "canon", "sony", "fuji", "olympus",
    ]

    // MARK: - Discovery

    static func discover(at root: URL, kind: IngestSourceKind? = nil) async -> IngestDiscovery? {
        let result = MediaFormats.discoverPhotos(at: root)
        guard !result.importable.isEmpty else { return nil }

        let materialized = await CloudFileMaterializer.prepareForImport(result.importable)
        guard !materialized.ready.isEmpty else { return nil }

        var skipped = result.skipped + materialized.skipped
        let resolvedKind = kind ?? SourceCatalog.classifyPath(root)
        let taste = detectTasteFolder(near: root, photoSample: materialized.ready)
        let bytes = materialized.ready.reduce(Int64(0)) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + Int64(size)
        }

        let manifest = IngestManifest(
            sourceRoot: root.path,
            sourceKind: resolvedKind,
            discoveredAt: Date(),
            filesDiscovered: result.discoveredCount,
            filesImported: materialized.ready.count,
            filesSkipped: skipped,
            filesFailed: [],
            exifDateMin: nil,
            exifDateMax: nil,
            totalBytes: bytes
        )

        return IngestDiscovery(
            sourceRoot: root,
            sourceKind: resolvedKind,
            photoURLs: materialized.ready,
            tasteFolder: taste,
            manifest: manifest
        )
    }

    static func bestIngestRoot(on volume: URL) -> URL? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: volume.path, isDirectory: &isDir), isDir.boolValue else { return nil }

        var candidates: [(url: URL, score: Int)] = [(volume, scoreVolume(volume))]

        if let kids = try? fm.contentsOfDirectory(
            at: volume,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for kid in kids {
                guard (try? kid.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let name = kid.lastPathComponent.lowercased()
                var score = 0
                if cameraRootMarkers.contains(where: { name.contains($0) }) { score += 5 }
                if name == "dcim" { score += 8 }
                let count = MediaFormats.discoverPhotos(at: kid).importable.count
                if count >= 10 { score += 4 }
                else if count >= 3 { score += 2 }
                if count > 0 { candidates.append((kid, score + min(count / 10, 5))) }
            }
        }

        let best = candidates.max(by: { $0.score < $1.score })
        guard let best, best.score >= 3 else { return nil }
        return best.url
    }

    static func scoreVolume(_ volume: URL) -> Int {
        var score = 0
        if isRemovableVolume(volume) { score += 4 }
        let name = volume.lastPathComponent.lowercased()
        if ["no name", "eos_digital", "untitled", "sd", "card"].contains(where: { name.contains($0) }) {
            score += 2
        }
        let count = MediaFormats.discoverPhotos(at: volume).importable.count
        if count >= 10 { score += 4 }
        else if count >= 3 { score += 2 }
        return score
    }

    static func isRemovableVolume(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsRemovableKey]).volumeIsRemovable) == true
            || (try? url.resourceValues(forKeys: [.volumeIsEjectableKey]).volumeIsEjectable) == true
    }

    static func shouldAutoIngest(volume: URL) -> Bool {
        guard IngestPreferences.autoIngestOnMount else { return false }
        guard volume.path.hasPrefix("/Volumes/") else { return false }
        guard volume.lastPathComponent != "Macintosh HD" else { return false }
        guard let root = bestIngestRoot(on: volume) else { return false }
        let count = MediaFormats.discoverPhotos(at: root, maxDepth: 6).importable.count
        if SourceCatalog.isIPhoneVolume(volume) { return count >= 1 }
        if IngestOrchestrator.isRemovableVolume(volume) { return count >= 1 }
        return count >= 3
    }

    static func mountedCandidateVolumes() -> [URL] {
        SourceCatalog.mountedPhotoVolumes()
    }

    // MARK: - Taste

    static func detectTasteFolder(near root: URL, photoSample: [URL]) -> URL? {
        if let remembered = IngestPreferences.lastTasteFolderPath {
            let url = URL(fileURLWithPath: remembered)
            if FileManager.default.fileExists(atPath: url.path),
               MediaFormats.countImportable(in: url) > 0 {
                return url
            }
        }

        let fm = FileManager.default
        var searchRoots: [URL] = [root.deletingLastPathComponent()]
        if root.path.contains("/DCIM/") {
            searchRoots.append(root.deletingLastPathComponent().deletingLastPathComponent())
        }
        searchRoots.append(root)

        for base in searchRoots {
            guard let kids = try? fm.contentsOfDirectory(
                at: base,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for kid in kids {
                guard (try? kid.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let name = kid.lastPathComponent.lowercased()
                guard tasteSiblingNames.contains(name) else { continue }
                guard MediaFormats.countImportable(in: kid) >= 3 else { continue }
                // Avoid using the same folder as RAW source
                if kid.standardizedFileURL == root.standardizedFileURL { continue }
                IngestPreferences.lastTasteFolderPath = kid.path
                return kid
            }
        }

        // Heuristic: JPG folder with matching filenames next to RAW tree
        if let sample = photoSample.first {
            let rawStem = sample.deletingPathExtension().lastPathComponent
            for base in searchRoots {
                guard let kids = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { continue }
                for kid in kids where kid.hasDirectoryPath {
                    let jpg = kid.appendingPathComponent("\(rawStem).jpg")
                    let jpeg = kid.appendingPathComponent("\(rawStem).jpeg")
                    if fm.fileExists(atPath: jpg.path) || fm.fileExists(atPath: jpeg.path) {
                        IngestPreferences.lastTasteFolderPath = kid.path
                        return kid
                    }
                }
            }
        }

        return nil
    }

    static func defaultJobBrief(photoCount: Int) -> JobBrief {
        if let target = IngestPreferences.lastTargetKeepCount {
            return JobBrief(
                targetKeepCount: min(target, photoCount),
                keepRate: IngestPreferences.lastKeepRate,
                autoDeliver: false
            )
        }
        let target = max(1, Int((Double(photoCount) * IngestPreferences.lastKeepRate).rounded()))
        return JobBrief(targetKeepCount: target, keepRate: IngestPreferences.lastKeepRate)
    }

    static func saveJobBriefDefaults(_ brief: JobBrief, photoCount: Int) {
        IngestPreferences.lastKeepRate = brief.resolvedKeepRate(totalPhotos: photoCount)
        if let target = brief.targetKeepCount {
            IngestPreferences.lastTargetKeepCount = target
        }
    }

    static func saveManifest(_ manifest: IngestManifest, projectName: String) {
        guard let dir = try? ProjectStore.projectDirectory(for: projectName) else { return }
        let url = dir.appendingPathComponent("ingest_manifest.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
