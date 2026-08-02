import Foundation

/// Resolves real-world photo sources: SD cards, external drives, iCloud, iPhone, local folders.
enum SourceCatalog {
    /// Well-known roots to scan on launch and when cloud files change.
    static func watchableRoots() -> [URL] {
        var roots: [URL] = []
        let home = FileManager.default.homeDirectoryForCurrentUser

        // iCloud Drive (Photos uploads, user folders)
        let cloudDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if FileManager.default.fileExists(atPath: cloudDocs.path) {
            roots.append(cloudDocs)
        }
        let iCloudAlias = home.appendingPathComponent("iCloud Drive", isDirectory: true)
        if FileManager.default.fileExists(atPath: iCloudAlias.path) {
            roots.append(iCloudAlias)
        }

        // Common local ingest folders
        let pictures = home.appendingPathComponent("Pictures", isDirectory: true)
        if FileManager.default.fileExists(atPath: pictures.path) {
            roots.append(pictures)
        }

        let luminaInbox = pictures.appendingPathComponent("Lumina/Inbox", isDirectory: true)
        if FileManager.default.fileExists(atPath: luminaInbox.path) {
            roots.append(luminaInbox)
        }

        return roots
    }

    /// All mounted volumes that may contain photos (SD, HDD, iPhone).
    static func mountedPhotoVolumes() -> [URL] {
        let keys: [URLResourceKey] = [
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeNameKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        return urls.filter { volume in
            guard volume.path.hasPrefix("/Volumes/") else { return false }
            let name = volume.lastPathComponent
            if name == "Macintosh HD" || name.hasPrefix(".") { return false }

            let values = try? volume.resourceValues(forKeys: Set(keys))
            let isInternal = values?.volumeIsInternal == true
            let isRemovable = values?.volumeIsRemovable == true || values?.volumeIsEjectable == true
            let photoCount = MediaFormats.discoverPhotos(at: volume, maxDepth: 6).importable.count

            // External HDD (non-removable USB), SD, or iPhone with photos
            if photoCount >= 3 { return true }
            if isRemovable && photoCount >= 1 { return true }
            if !isInternal && photoCount >= 1 { return true }
            if classifyVolume(volume) == .iPhone { return photoCount >= 1 }
            return false
        }
    }

    static func classifyVolume(_ volume: URL) -> IngestSourceKind {
        let name = volume.lastPathComponent.lowercased()
        if name.contains("iphone") || name.contains("ipad") || name.contains("ios") {
            return .iPhone
        }
        if (try? volume.resourceValues(forKeys: [.volumeIsRemovableKey]).volumeIsRemovable) == true {
            return .sdCard
        }
        if volume.path.hasPrefix("/Volumes/") {
            return .externalDrive
        }
        return .localFolder
    }

    static func classifyPath(_ url: URL) -> IngestSourceKind {
        let path = url.path
        if path.contains("Mobile Documents/com~apple~CloudDocs") || path.contains("iCloud Drive") {
            return .iCloud
        }
        if path.contains("/Volumes/") {
            return classifyVolume(url)
        }
        return .localFolder
    }

    static func isIPhoneVolume(_ volume: URL) -> Bool {
        classifyVolume(volume) == .iPhone
    }
}

/// Ensures iCloud and placeholder files are fully downloaded before import.
enum CloudFileMaterializer {
    enum MaterializeError: Error {
        case cloudOnlyPlaceholder
        case downloadTimedOut
        case zeroByteFile
    }

    /// Prepare files for import — download iCloud evicted files, reject zero-byte stubs.
    static func prepareForImport(_ urls: [URL]) async -> (ready: [URL], skipped: [IngestSkippedFile]) {
        var ready: [URL] = []
        var skipped: [IngestSkippedFile] = []

        for url in urls {
            do {
                let materialized = try await materialize(url)
                ready.append(materialized)
            } catch {
                let reason: IngestSkipReason = switch error {
                case MaterializeError.cloudOnlyPlaceholder: .cloudPlaceholder
                case MaterializeError.zeroByteFile: .cloudPlaceholder
                default: .unsupported
                }
                skipped.append(IngestSkippedFile(path: url.path, reason: reason))
            }
        }
        return (ready, skipped)
    }

    static func materialize(_ url: URL) async throws -> URL {
        if isICloudPlaceholderSibling(url) {
            throw MaterializeError.cloudOnlyPlaceholder
        }

        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .isUbiquitousItemKey,
        ])

        let size = values?.fileSize ?? 0
        if size == 0 && values?.isUbiquitousItem != true {
            throw MaterializeError.zeroByteFile
        }

        guard values?.isUbiquitousItem == true else {
            if size == 0 { throw MaterializeError.zeroByteFile }
            return url
        }

        let status = values?.ubiquitousItemDownloadingStatus
        if status == URLUbiquitousItemDownloadingStatus.current {
            return url
        }

        try FileManager.default.startDownloadingUbiquitousItem(at: url)

        // Poll until downloaded or timeout (~45s per file)
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 250_000_000)
            let check = try? url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .fileSizeKey,
            ])
            if check?.ubiquitousItemDownloadingStatus == .current, (check?.fileSize ?? 0) > 0 {
                return url
            }
            if check?.ubiquitousItemDownloadingStatus == .notDownloaded {
                continue
            }
        }

        let final = try? url.resourceValues(forKeys: [.fileSizeKey, .ubiquitousItemDownloadingStatusKey])
        if (final?.fileSize ?? 0) > 0 {
            return url
        }
        throw MaterializeError.downloadTimedOut
    }

    /// iCloud evicted files appear as `photo.HEIC.icloud` with zero-byte stub alongside.
    private static func isICloudPlaceholderSibling(_ url: URL) -> Bool {
        let icloudSibling = URL(fileURLWithPath: url.path + ".icloud")
        if FileManager.default.fileExists(atPath: icloudSibling.path) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size == 0
        }
        if url.pathExtension.lowercased() == "icloud" { return true }
        return false
    }

    static func sourceQualityLabel(for url: URL) -> String {
        let ext = url.pathExtension.uppercased()
        if MediaFormats.knownExtensions.contains(ext) && !["ARW", "CR2", "CR3", "NEF", "DNG", "ORF", "RAF"].contains(ext) {
            return "full"
        }
        if (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 8_000_000 {
            return "full"
        }
        return "embedded"
    }
}
