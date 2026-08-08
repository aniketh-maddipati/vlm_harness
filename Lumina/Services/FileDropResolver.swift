import Foundation
import UniformTypeIdentifiers

/// Shared NSItemProvider → URL collection for folder / file drops.
enum FileDropResolver {
    /// Load file URLs from drop providers, then invoke `completion` on the main queue.
    /// - Parameter requireFileURLType: When true, only providers advertising `UTType.fileURL` are loaded
    ///   (legacy ContentView path). When false, every provider is attempted (P0 open path).
    static func collectURLs(
        from providers: [NSItemProvider],
        requireFileURLType: Bool = true,
        completion: @escaping ([URL]) -> Void
    ) {
        let lock = NSLock()
        var collected: [URL] = []
        let group = DispatchGroup()
        let typeID = UTType.fileURL.identifier

        for provider in providers {
            if requireFileURLType, !provider.hasItemConformingToTypeIdentifier(typeID) {
                continue
            }
            group.enter()
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                if let url {
                    lock.lock()
                    collected.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            completion(collected)
        }
    }
}
