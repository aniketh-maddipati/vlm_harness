import CryptoKit
import Foundation

/// Stable asset identity independent of grid position and discovery order.
/// Prefer this over ephemeral `UUID()` assignment at import.
enum AssetIdentity {
    /// Schema for the opaque source key that seeds a deterministic UUID.
    static let keyVersion = 1

    /// Build a rediscovery key from volume identity, relative path, size, and capture time.
    /// Filename alone is never sufficient — nested duplicates must remain distinct.
    static func sourceKey(
        volumeID: String?,
        relativePath: String,
        fileSize: Int64?,
        capturedAt: Date?
    ) -> String {
        let vol = volumeID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let rel = normalizeRelativePath(relativePath)
        let size = fileSize.map(String.init) ?? ""
        let stamp: String
        if let capturedAt {
            stamp = String(format: "%.3f", capturedAt.timeIntervalSince1970)
        } else {
            stamp = ""
        }
        return "v\(keyVersion)|\(vol)|\(rel)|\(size)|\(stamp)"
    }

    /// Deterministic UUID derived from a source key (SHA-256 truncated to 16 bytes).
    /// When `preserved` is provided (legacy project migration), that ID wins.
    static func resolveID(sourceKey: String, preserved: UUID? = nil) -> UUID {
        if let preserved { return preserved }
        return uuid(from: sourceKey)
    }

    /// Relative path of `file` under `root`, falling back to the filename.
    static func relativePath(file: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            let start = filePath.index(filePath.startIndex, offsetBy: rootPath.count)
            var rel = String(filePath[start...])
            if rel.hasPrefix("/") { rel.removeFirst() }
            return normalizeRelativePath(rel.isEmpty ? file.lastPathComponent : rel)
        }
        return normalizeRelativePath(file.lastPathComponent)
    }

    /// Volume UUID when available (external drives), else volume name, else empty.
    static func volumeIdentifier(for url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [
            .volumeIdentifierKey,
            .volumeUUIDStringKey,
            .volumeNameKey,
        ])
        if let uuid = values?.volumeUUIDString, !uuid.isEmpty { return uuid }
        if let name = values?.volumeName, !name.isEmpty { return "name:\(name)" }
        return nil
    }

    static func fileSize(of url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize { return Int64(size) }
        return nil
    }

    /// Cache filename stem keyed by asset identity — not the source filename stem.
    static func cacheStem(for assetID: UUID) -> String {
        assetID.uuidString.lowercased()
    }

    /// One-shot copy of a stem-keyed cache file into the identity-keyed location when missing.
    static func migrateLegacyCache(from legacy: URL, to identityURL: URL) {
        guard !FileManager.default.fileExists(atPath: identityURL.path),
              FileManager.default.fileExists(atPath: legacy.path) else { return }
        try? FileManager.default.copyItem(at: legacy, to: identityURL)
    }

    // MARK: - Internals

    private static func normalizeRelativePath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .filter { $0 != "." && !$0.isEmpty }
            .joined(separator: "/")
            .lowercased()
    }

    private static func uuid(from sourceKey: String) -> UUID {
        let digest = SHA256.hash(data: Data(sourceKey.utf8))
        var bytes = Array(digest.prefix(16))
        // RFC 4122 variant + version 5-ish markers so the UUID is well-formed.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
