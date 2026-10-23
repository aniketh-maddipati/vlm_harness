import Foundation

// Stand-ins for the app types the tracker's files name but the mask lab never calls: SetsMasks' preview cache reads
// through SetsIngest, and SkimFollow.matteName goes through SkimExport.safeName (the matte is not written here).
nonisolated final class SetsIngest: @unchecked Sendable {
    struct Preview: Hashable, Sendable { var rel: String; var length: Int = 0 }
    func isGone(_ rel: String) -> Bool { true }
    func preview(_ p: Preview) throws -> Data { Data() }
}

nonisolated enum SkimExport {
    static func safeName(_ suggested: String, allowed: Set<String> = []) -> String? { suggested }
}
