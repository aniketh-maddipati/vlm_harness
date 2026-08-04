import Foundation

/// Finds same-subject, lower-quality peers worth batch-culling after a user decision.
enum PeerCullEngine {

    private static let scoreMargin = 0.04

    /// After keeping a frame, suggest cutting softer undecided peers in the same cluster/burst.
    static func cutSuggestion(afterKeeping photoID: UUID, in photos: [PhotoRecord]) -> [PhotoRecord]? {
        guard let anchor = photos.first(where: { $0.id == photoID }) else { return nil }
        let peers = undecidedPeers(of: anchor, in: photos)
            .filter { $0.cullScore < anchor.cullScore - scoreMargin }
            .sorted { $0.cullScore < $1.cullScore }
        return peers.isEmpty ? nil : peers
    }

    /// After cutting a frame, suggest cutting equally soft or softer undecided peers.
    static func cutSuggestion(afterCutting photoID: UUID, in photos: [PhotoRecord]) -> [PhotoRecord]? {
        guard let anchor = photos.first(where: { $0.id == photoID }) else { return nil }
        let peers = undecidedPeers(of: anchor, in: photos)
            .filter { $0.cullScore <= anchor.cullScore + scoreMargin }
            .sorted { $0.cullScore < $1.cullScore }
        return peers.isEmpty ? nil : peers
    }

    private static func undecidedPeers(of anchor: PhotoRecord, in photos: [PhotoRecord]) -> [PhotoRecord] {
        let subjectKey = anchor.clusterID ?? anchor.burstID
        guard let subjectKey else { return [] }
        return photos.filter { photo in
            guard photo.id != anchor.id else { return false }
            guard photo.tier == .unranked, !photo.isFlagged else { return false }
            guard !photo.isBurstHero, !photo.isClusterHero else { return false }
            let peerKey = photo.clusterID ?? photo.burstID
            return peerKey == subjectKey
        }
    }
}
