import Foundation
import CoreGraphics

/// Immutable fixture factories for Xcode previews and offline shell verification.
enum PresentationFixtures {

    static func asset(
        name: String,
        aspect: CGFloat = 3.0 / 2.0,
        decision: AssetDecision = .undecided,
        protected: Bool = false,
        caption: String? = nil
    ) -> AssetPresentation {
        AssetPresentation(
            filename: name,
            aspectRatio: aspect,
            decision: decision,
            isProtected: protected,
            caption: caption
        )
    }

    private static let brooklynAssets: [AssetPresentation] = [
        asset(name: "DSC01201.ARW", aspect: 3.0 / 2.0, decision: .keep),
        asset(name: "DSC01202.ARW", aspect: 3.0 / 2.0),
        asset(name: "DSC01203.ARW", aspect: 2.0 / 3.0),
        asset(name: "DSC01204.ARW", aspect: 3.0 / 2.0, decision: .needsMe),
        asset(name: "DSC01205.ARW", aspect: 3.0 / 2.0, decision: .cut),
        asset(name: "DSC01206.ARW", aspect: 4.0 / 5.0, decision: .anchor, protected: true),
        asset(name: "DSC01207.ARW", aspect: 3.0 / 2.0),
        asset(name: "DSC01208.ARW", aspect: 16.0 / 9.0),
    ]

    static func homeNewSDCard() -> HomePresentation {
        let card = ShootCardPresentation(
            id: "new-sd",
            title: "Untitled shoot",
            subtitle: "Card just mounted",
            dateLabel: "Today · 4:12 PM",
            photographCount: 642,
            progressLabel: "642 new photographs · 2 proposed shoots",
            previewAssets: Array(brooklynAssets.prefix(3)),
            readiness: .findingMore,
            primaryActionTitle: "Review new photographs"
        )
        return HomePresentation(
            greeting: greeting(),
            newSection: .init(
                headline: "New",
                detail: "642 new photographs · 2 proposed shoots",
                card: card,
                actionTitle: "Review new photographs"
            ),
            continueSection: resumedProjectCard(),
            recentlyFinished: [
                FinishedStripItem(
                    id: "queens",
                    title: "Queens Night Walk",
                    photographCount: 18,
                    thumbAssets: Array(brooklynAssets.prefix(4))
                )
            ],
            readinessSummary: "12 shoots ready · finding more"
        )
    }

    static func homeResumed() -> HomePresentation {
        HomePresentation(
            greeting: greeting(),
            newSection: nil,
            continueSection: resumedProjectCard(),
            recentlyFinished: [
                FinishedStripItem(
                    id: "queens",
                    title: "Queens Night Walk",
                    photographCount: 18,
                    thumbAssets: Array(brooklynAssets.prefix(4))
                )
            ],
            readinessSummary: nil
        )
    }

    static func homeEmpty() -> HomePresentation {
        HomePresentation(
            greeting: greeting(),
            newSection: nil,
            continueSection: nil,
            recentlyFinished: [],
            readinessSummary: "Open a shoot to begin"
        )
    }

    static func homeDisconnected() -> HomePresentation {
        let base = resumedProjectCard()
        let card = ShootCardPresentation(
            id: base.id,
            title: base.title,
            subtitle: "Source disconnected",
            dateLabel: base.dateLabel,
            locationLabel: base.locationLabel,
            photographCount: base.photographCount,
            progressLabel: "Reconnect the card to continue",
            previewAssets: base.previewAssets,
            readiness: .disconnected,
            boundaryWarning: "Last seen on Untitled SD Card",
            primaryActionTitle: "Reconnect"
        )
        return HomePresentation(
            greeting: greeting(),
            newSection: nil,
            continueSection: card,
            recentlyFinished: [],
            readinessSummary: "1 shoot waiting on a source"
        )
    }

    static func shootSelection() -> ShootSelectionPresentation {
        ShootSelectionPresentation(
            readinessSummary: "12 shoots ready · finding more",
            shoots: [
                ShootCardPresentation(
                    id: "s1",
                    title: "Brooklyn Waterfront",
                    dateLabel: "Aug 2 · 6:40 PM",
                    locationLabel: "Red Hook",
                    photographCount: 186,
                    previewAssets: Array(brooklynAssets.prefix(5)),
                    readiness: .ready
                ),
                ShootCardPresentation(
                    id: "s2",
                    title: "Golden Hour Portraits",
                    dateLabel: "Aug 1 · 7:15 PM",
                    locationLabel: "Prospect Park",
                    photographCount: 94,
                    previewAssets: Array(brooklynAssets.suffix(4)),
                    readiness: .ready,
                    boundaryWarning: "May include the next walk"
                ),
                ShootCardPresentation(
                    id: "s3",
                    title: "Studio Day",
                    dateLabel: "Jul 28 · 11:02 AM",
                    photographCount: 312,
                    previewAssets: Array(brooklynAssets.prefix(3)),
                    readiness: .findingMore
                ),
            ]
        )
    }

    static func shootUncertainBoundary() -> ShootSelectionPresentation {
        let base = shootSelection()
        let warned = ShootCardPresentation(
            id: "boundary",
            title: "Card boundary",
            dateLabel: "Aug 3 · 9:18 AM",
            photographCount: 48,
            previewAssets: Array(brooklynAssets.prefix(3)),
            readiness: .ready,
            boundaryWarning: "Timestamps suggest two shoots may be joined"
        )
        return ShootSelectionPresentation(
            readinessSummary: base.readinessSummary,
            shoots: [warned] + base.shoots
        )
    }

    static func attemptWorkspace() -> WorkspacePresentation {
        let groups = attemptGroups()
        return WorkspacePresentation(
            shootTitle: "Brooklyn Waterfront",
            lens: .attempts,
            groups: groups,
            selectedAssetID: groups[0].assets[1].id,
            selectedGroupID: groups[0].id,
            progressCurrent: 8,
            progressTotal: 31,
            inspectorAvailable: true
        )
    }

    static func lightWorkspace() -> WorkspacePresentation {
        let groups = lightGroups()
        return WorkspacePresentation(
            shootTitle: "Brooklyn Waterfront",
            lens: .light,
            groups: groups,
            selectedAssetID: groups[0].representativeID,
            selectedGroupID: groups[0].id,
            progressCurrent: 8,
            progressTotal: 31,
            inspectorAvailable: true
        )
    }

    static func finishedSet() -> FinishPresentation {
        let kept = brooklynAssets.filter { $0.decision == .keep || $0.decision == .anchor || $0.decision == .undecided }
            .map {
                AssetPresentation(
                    id: $0.id,
                    filename: $0.filename,
                    aspectRatio: $0.aspectRatio,
                    decision: $0.decision == .undecided ? .keep : $0.decision,
                    isProtected: $0.isProtected
                )
            }
        return FinishPresentation(
            shootTitle: "Brooklyn Waterfront",
            assets: Array(kept.prefix(7)),
            unresolvedCount: 3,
            protectedCount: kept.filter(\.isProtected).count,
            primaryActionTitle: "Finish",
            secondaryReviewTitle: "Review unresolved"
        )
    }

    static func missingSourceFinish() -> FinishPresentation {
        FinishPresentation(
            shootTitle: "Brooklyn Waterfront",
            assets: Array(brooklynAssets.prefix(3)),
            unresolvedCount: 0,
            protectedCount: 1,
            primaryActionTitle: "Export when source returns",
            secondaryReviewTitle: "Review"
        )
    }

    private static func resumedProjectCard() -> ShootCardPresentation {
        ShootCardPresentation(
            id: "continue-brooklyn",
            title: "Brooklyn Waterfront",
            dateLabel: "Aug 2 · 6:40 PM",
            locationLabel: "Red Hook",
            photographCount: 186,
            progressLabel: "14 of 28 attempts reviewed",
            previewAssets: Array(brooklynAssets.prefix(4)),
            readiness: .ready,
            primaryActionTitle: "Continue"
        )
    }

    private static func attemptGroups() -> [GroupPresentation] {
        let a = Array(brooklynAssets.prefix(5))
        let b = Array(brooklynAssets.suffix(3))
        return [
            GroupPresentation(
                id: "attempt-01",
                title: "Attempt 01",
                subtitle: "Same subject · similar composition",
                assets: a,
                representativeID: a.first?.id,
                relationshipNote: "14 seconds"
            ),
            GroupPresentation(
                id: "attempt-02",
                title: "Attempt 02",
                subtitle: "Wider frame",
                assets: b,
                representativeID: b.first?.id,
                relationshipNote: "41 seconds later"
            ),
        ]
    }

    private static func lightGroups() -> [GroupPresentation] {
        let cool = Array(brooklynAssets.prefix(4))
        let warm = Array(brooklynAssets.suffix(4))
        return [
            GroupPresentation(
                id: "palette-cool",
                title: "Cool open shade",
                subtitle: "Related tonal family",
                assets: cool,
                representativeID: cool.first?.id,
                relationshipNote: "Photographs are the palette"
            ),
            GroupPresentation(
                id: "palette-warm",
                title: "Warm sidelight",
                subtitle: "Related tonal family",
                assets: warm,
                representativeID: warm.first?.id,
                relationshipNote: nil
            ),
        ]
    }

    private static func greeting(now: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}
