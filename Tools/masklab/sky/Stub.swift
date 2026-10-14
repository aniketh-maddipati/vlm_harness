import Foundation

// SetsMasks keeps a cache keyed by the app's previews; the sky test calls only its static finders,
// so this stands in for the app's reader.
nonisolated final class SetsIngest: @unchecked Sendable {
    struct Preview: Hashable, Sendable { var rel: String; var length: Int = 0 }
    func isGone(_ rel: String) -> Bool { true }
    func preview(_ p: Preview) throws -> Data { Data() }
}
