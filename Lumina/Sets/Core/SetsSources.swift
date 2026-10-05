import Foundation

/// The ordered source references that make up one shoot. The stored path is display metadata
/// only: availability and reconnection always go through the security-scoped bookmark.
nonisolated struct SetsSources: Codable {
    struct Source: Codable, Equatable {
        var id: String
        var kind: String
        var label: String
        var path: String
        var bookmark: Data
        var added: Date
    }

    private(set) var sources: [Source]
    private var calls: SetsAccess.Calls
    private var now: () -> Date

    init(sources: [Source] = [], calls: SetsAccess.Calls = .system, now: @escaping () -> Date = Date.init) {
        self.sources = sources
        self.calls = calls
        self.now = now
    }

    private enum CodingKeys: String, CodingKey { case sources }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sources = try values.decode([Source].self, forKey: .sources)
        calls = .system
        now = Date.init
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sources, forKey: .sources)
    }

    private static func realPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func newID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))
    }

    /// Adds a panel or drop grant. Existing bookmarks, not their display paths, decide whether
    /// this folder is already part of the shoot.
    mutating func add(url: URL, kind: String, label: String) throws -> Source {
        let path = Self.realPath(url)
        for source in sources {
            guard let resolved = try? calls.resolve(source.bookmark) else { continue }
            if Self.realPath(resolved.url) == path { return source }
        }
        let source = Source(id: Self.newID(), kind: kind, label: label, path: url.path,
                            bookmark: try calls.bookmark(url), added: now())
        sources.append(source)
        return source
    }

    /// Missing means the bookmark itself is unavailable or no directory exists at its result.
    /// In particular, this never probes a source's last-known path.
    func status() -> [(id: String, missing: Bool)] {
        sources.map { source in
            guard let resolved = try? calls.resolve(source.bookmark) else {
                return (source.id, true)
            }
            return (source.id, !calls.exists(resolved.url))
        }
    }

    /// Resolves an existing grant. A stale grant is renewed in place, preserving source identity
    /// and order. Access lifetime remains the caller's responsibility.
    mutating func reconnect(_ id: String) -> URL? {
        guard let index = sources.firstIndex(where: { $0.id == id }),
              let resolved = try? calls.resolve(sources[index].bookmark),
              calls.exists(resolved.url) else { return nil }
        if resolved.stale, let bookmark = try? calls.bookmark(resolved.url) {
            sources[index].bookmark = bookmark
            sources[index].path = resolved.url.path
        }
        return resolved.url
    }

    /// Replaces a missing grant with a folder the caller obtained from a panel.
    @discardableResult
    mutating func relocate(_ id: String, to url: URL) throws -> Source? {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return nil }
        sources[index].bookmark = try calls.bookmark(url)
        sources[index].path = url.path
        return sources[index]
    }

    mutating func remove(_ id: String) {
        sources.removeAll { $0.id == id }
    }
}
