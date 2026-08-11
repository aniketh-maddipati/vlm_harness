import Foundation

/// Goal-directed policy — adjusts keep rate, collections, and auto-resolve thresholds from JobBrief.
enum PhotoAgentOrchestrator {
    static func applyBrief(_ brief: JobBrief, to project: inout LuminaProject) {
        project.keepRateTarget = brief.resolvedKeepRate(totalPhotos: project.photos.count)
        project.jobBrief = brief
    }

    static func planAfterImport(photos: [PhotoRecord], brief: JobBrief) -> String {
        let rate = brief.resolvedKeepRate(totalPhotos: photos.count)
        let target = Int((Double(photos.count) * rate).rounded())
        let uncertain = photos.filter(\.isUncertain).count
        return "Plan: ~\(target) keeps from \(photos.count) · \(uncertain) need you · \(brief.eventType.label)"
    }

    static func draftCollections(for photos: [PhotoRecord], brief: JobBrief) -> [ExportCollection] {
        let keeps = photos.filter { $0.tier == .keep }.sorted { $0.cullScore > $1.cullScore }
        let heroCount = min(12, max(4, keeps.count / 5))
        let carouselCount = min(keeps.count, brief.targetKeepCount ?? keeps.count)
        let reelCount = min(8, max(4, keeps.count / 8))
        let heroes = keeps.filter { $0.isBurstHero || $0.isClusterHero }
        let heroIDs = Array((heroes.isEmpty ? keeps : heroes).prefix(heroCount).map(\.id))
        return [
            ExportCollection(name: "heroes", aspect: .fourByFive, photoIDs: heroIDs),
            ExportCollection(name: "grid_carousel", aspect: .fourByFive, photoIDs: Array(keeps.prefix(carouselCount).map(\.id))),
            ExportCollection(name: "reel_sequence", aspect: .nineBySixteen, photoIDs: Array(keeps.prefix(reelCount).map(\.id))),
        ]
    }

    /// Auto-resolve burst ties when score delta exceeds learned threshold.
    static func autoResolveHighConfidence(in photos: inout [PhotoRecord], threshold: Double) -> [AgentAction] {
        var actions: [AgentAction] = []
        let burstGroups = Dictionary(grouping: photos, by: { $0.burstID ?? "single-\($0.id)" })

        for (_, group) in burstGroups where group.count >= 2 {
            let sorted = group.sorted { $0.cullScore > $1.cullScore }
            guard sorted.count >= 2 else { continue }
            let delta = sorted[0].cullScore - sorted[1].cullScore
            if delta >= threshold {
                for i in 1..<sorted.count {
                    guard let idx = photos.firstIndex(where: { $0.id == sorted[i].id }),
                          photos[idx].isUncertain,
                          photos[idx].uncertaintyKind == .cullTie else { continue }
                    photos[idx].tier = .reject
                    photos[idx].isFlagged = false
                    photos[idx].uncertaintyKind = .none
                    photos[idx].whyUncertain = nil
                    photos[idx].whyAction = "Auto-rejected burst duplicate (Δ\(String(format: "%.2f", delta)))"
                    photos[idx].cullConfidence = 0.88
                    actions.append(AgentAction(
                        photoID: sorted[i].id,
                        clusterID: sorted[i].clusterID,
                        kind: .autoReject,
                        whyAction: photos[idx].whyAction ?? "Burst tie resolved"
                    ))
                }
            }
        }
        return actions
    }

    static func recordAutoActions(_ actions: [AgentAction], log: inout [AgentAction]) {
        log.append(contentsOf: actions)
    }

    static func buildSessionSummary(
        photos: [PhotoRecord],
        agentLog: [AgentAction],
        feedbackCount: Int
    ) -> SessionSummary {
        SessionSummary(
            totalPhotos: photos.count,
            keepCount: photos.filter { $0.tier == .keep }.count,
            rejectCount: photos.filter { $0.tier == .reject }.count,
            uncertainResolved: agentLog.filter { $0.kind == .stackResolve || $0.kind == .autoReject }.count,
            autoActions: agentLog.filter { $0.kind == .autoKeep || $0.kind == .autoReject || $0.kind == .autoHero }.count,
            userOverrides: agentLog.filter {
                $0.kind == .userKeep || $0.kind == .userReject || $0.kind == .userHero
            }.count,
            feedbackEvents: feedbackCount
        )
    }
}
