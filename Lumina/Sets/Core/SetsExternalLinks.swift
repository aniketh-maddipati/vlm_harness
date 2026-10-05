import Foundation

enum SetsExternalLinks {
    // Sets v7 Beta panel and ? sheet: Report a bug, LinkedIn, and X.
    static let bugReportRecipient = "anikethcov@gmail.com"
    static let linkedIn = URL(string: "https://www.linkedin.com/in/anikethmaddipati/")!
    static let x = URL(string: "https://x.com/aniketh745")!

    enum Verdict: Equatable {
        case inPage
        case external(URL)
        case refuse(String)
    }

    /// Keeps the page offline: only a user's click may hand one of the three documented
    /// destinations to the native shell, and accepted URLs are rebuilt or canonicalized first.
    static func verdict(for url: URL, userClicked: Bool) -> Verdict {
        let scheme = url.scheme?.lowercased()

        if scheme == "lumina" {
            return .inPage
        }
        if url.absoluteString == "about:blank" {
            return .inPage
        }

        guard userClicked else {
            return .refuse("external navigation requires a user click")
        }

        switch scheme {
        case "mailto":
            return mailVerdict(url)
        case "https":
            return webVerdict(url)
        default:
            return .refuse("scheme is not allowed")
        }
    }

    private static func mailVerdict(_ url: URL) -> Verdict {
        guard url.absoluteString.count <= 2_000 else {
            return .refuse("bug report link is too long")
        }
        // The text itself is checked for a fragment: for a URL without "//" some macOS versions leave
        // `fragment` nil and keep "#…" in the query's last value (seen on CI's runner, not on macOS 26).
        guard url.fragment == nil, !url.absoluteString.contains("#"),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.host == nil, parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path == bugReportRecipient else {
            return .refuse("bug report recipient is not allowed")
        }

        let items = parts.queryItems ?? []
        let allowed = Set(["subject", "body"])
        guard items.allSatisfy({ allowed.contains($0.name) }),
              Set(items.map(\.name)).count == items.count else {
            return .refuse("bug report query is not allowed")
        }

        var rebuilt = URLComponents()
        rebuilt.scheme = "mailto"
        rebuilt.path = bugReportRecipient
        rebuilt.queryItems = items.isEmpty ? nil : items
        guard let safe = rebuilt.url else {
            return .refuse("bug report link is invalid")
        }
        return .external(safe)
    }

    private static func webVerdict(_ url: URL) -> Verdict {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https",
              let host = parts.host?.lowercased(),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              !parts.percentEncodedPath.lowercased().contains("%2f") else {
            return .refuse("web link is not allowed")
        }

        let path = parts.path.count > 1 && parts.path.hasSuffix("/")
            ? String(parts.path.dropLast())
            : parts.path
        switch (host, path) {
        case ("www.linkedin.com", "/in/anikethmaddipati"):
            return .external(linkedIn)
        case ("x.com", "/aniketh745"):
            return .external(x)
        default:
            return .refuse("web destination is not allowed")
        }
    }
}
