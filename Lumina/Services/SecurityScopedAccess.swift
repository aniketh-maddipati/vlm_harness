import Foundation

/// Resolves and holds security-scoped folder access for a shoot source.
nonisolated enum SecurityScopedAccess {
    /// Resolve a stored bookmark (or fall back to the last-known path) and begin scoped access.
    static func resolveFolder(from reference: SourceReference?) throws -> (url: URL, didStartAccess: Bool) {
        guard let reference else {
            throw ShootStoreError.bookmarkResolveFailed("No source reference")
        }

        if let data = reference.bookmarkData {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                let started = url.startAccessingSecurityScopedResource()
                if FileManager.default.fileExists(atPath: url.path) {
                    return (url, started)
                }
                if started { url.stopAccessingSecurityScopedResource() }
            } catch {
                // Fall through to path recovery.
            }
        }

        let pathURL = URL(fileURLWithPath: reference.originalPath)
        if FileManager.default.fileExists(atPath: pathURL.path) {
            let started = pathURL.startAccessingSecurityScopedResource()
            return (pathURL, started)
        }

        throw ShootStoreError.bookmarkResolveFailed(
            "Missing folder at \(reference.originalPath)"
        )
    }

    static func stopIfNeeded(_ url: URL, didStartAccess: Bool) {
        guard didStartAccess else { return }
        url.stopAccessingSecurityScopedResource()
    }

    /// Create a security-scoped bookmark for a user-chosen folder.
    static func bookmark(for folderURL: URL) -> Data? {
        try? folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
