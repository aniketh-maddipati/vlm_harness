import Foundation

#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

/// Chooses where Add and Open panels begin without retaining access to anything the user did not
/// pick. Bookmarks are per button because "Downloads" and "Folder" are separate user intentions.
final class SetsOpenPlaces {
    enum Place: String, CaseIterable {
        case card, pictures, downloads, desktop, folder, phone

        init?(_ `where`: String) { self.init(rawValue: `where`) }
    }

    enum Start: Equatable {
        case panel(directory: URL?)
        case noCard
        case notAPicker
    }

    struct Calls {
        /// Resolves without UI or mounting a missing volume.
        var resolve: (Data) throws -> (url: URL, stale: Bool)
        var bookmark: (URL) throws -> Data
        var directoryExists: (URL) -> Bool
        var isDirectory: (URL) -> Bool

        static let system = Calls(
            resolve: { data in
                var stale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI, .withoutMounting],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale)
                return (url, stale)
            },
            bookmark: {
                try $0.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil)
            },
            directoryExists: { url in
                var directory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
                    && directory.boolValue
            },
            isDirectory: { url in
                var directory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
                    && directory.boolValue
            })
    }

    private let defaults: UserDefaults
    private let calls: Calls

    init(defaults: UserDefaults = .standard, calls: Calls = .system) {
        self.defaults = defaults
        self.calls = calls
    }

    func start(for place: Place, card: URL?) -> Start {
        switch place {
        case .phone:
            return .notAPicker
        case .card:
            guard let card else { return .noCard }
            let dcim = card.appendingPathComponent("DCIM", isDirectory: true)
            return .panel(directory: calls.directoryExists(dcim) ? dcim : card)
        case .pictures, .downloads, .desktop, .folder:
            if let remembered = remembered(for: place) {
                return .panel(directory: remembered)
            }
            return .panel(directory: defaultDirectory(for: place))
        }
    }

    /// Remembers the containing folder when a user chose a file. Cards and phones are live
    /// sources, not stable picker destinations, so they never create last-directory state.
    func remember(_ url: URL, for place: Place) {
        guard place != .card, place != .phone else { return }
        let folder = calls.isDirectory(url) ? url : url.deletingLastPathComponent()
        do {
            defaults.set(try calls.bookmark(folder), forKey: key(for: place))
        } catch {
            defaults.removeObject(forKey: key(for: place))
        }
    }

    func forget(_ place: Place) {
        defaults.removeObject(forKey: key(for: place))
    }

    private func remembered(for place: Place) -> URL? {
        let storageKey = key(for: place)
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        do {
            let result = try calls.resolve(data)
            guard !result.stale, calls.directoryExists(result.url) else {
                defaults.removeObject(forKey: storageKey)
                return nil
            }
            return result.url
        } catch {
            defaults.removeObject(forKey: storageKey)
            return nil
        }
    }

    private func defaultDirectory(for place: Place) -> URL? {
        let directory: FileManager.SearchPathDirectory
        switch place {
        case .pictures: directory = .picturesDirectory
        case .downloads: directory = .downloadsDirectory
        case .desktop: directory = .desktopDirectory
        case .folder, .card, .phone: return nil
        }
        return FileManager.default.urls(for: directory, in: .userDomainMask).first
    }

    private func key(for place: Place) -> String {
        "lumina.lastDir.\(place.rawValue)"
    }

    #if canImport(AppKit)
    /// Configures the picker only. The caller owns presentation and handling its result.
    @MainActor
    static func panel(start: URL?, add: Bool) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = start
        panel.prompt = add ? "Add to shoot" : "Open"
        panel.allowedContentTypes = [
            "com.sony.arw-raw-image",
            UTType.rawImage.identifier,
            "com.adobe.raw-image",
            UTType.folder.identifier,
        ].compactMap { UTType($0) }
        return panel
    }
    #endif
}
