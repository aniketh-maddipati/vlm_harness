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

    private static let deathValleyAssets: [AssetPresentation] = [
        asset(name: "DSC01201.ARW", aspect: 3.0 / 2.0, decision: .keep),
        asset(name: "DSC01202.ARW", aspect: 3.0 / 2.0),
        asset(name: "DSC01203.ARW", aspect: 2.0 / 3.0),
        asset(name: "DSC01204.ARW", aspect: 3.0 / 2.0, decision: .needsMe),
        asset(name: "DSC01205.ARW", aspect: 3.0 / 2.0, decision: .cut),
        asset(name: "DSC01206.ARW", aspect: 4.0 / 5.0, decision: .anchor, protected: true),
    ]

    private static let brooklynAssets: [AssetPresentation] = deathValleyAssets + [
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
            shootTitle: "Death Valley",
            lens: .attempts,
            groups: groups,
            selectedAssetID: groups[0].assets[1].id,
            selectedGroupID: groups[0].id,
            progressCurrent: 8,
            progressTotal: 31,
            inspectorAvailable: true
        )
    }

    /// Two-up comparison fixture for verification captures.
    static func twoUpComparison() -> WorkspacePresentation {
        let photos = [
            asset(name: "DSC02001.ARW", aspect: 3.0 / 2.0),
            asset(name: "DSC02002.ARW", aspect: 3.0 / 2.0),
        ]
        return WorkspacePresentation(
            shootTitle: "Death Valley",
            lens: .attempts,
            groups: [
                GroupPresentation(
                    id: "two-up",
                    title: "Ridge pair · 2 photographs",
                    subtitle: "2:14 PM",
                    assets: photos,
                    representativeID: photos[0].id
                ),
                GroupPresentation(
                    id: "idle-row",
                    title: "Later light · 3 photographs",
                    subtitle: "2:40 PM",
                    assets: Array(brooklynAssets.prefix(3)),
                    representativeID: brooklynAssets[0].id
                ),
            ],
            selectedAssetID: photos[0].id,
            selectedGroupID: "two-up",
            progressCurrent: 2,
            progressTotal: 5,
            inspectorAvailable: true
        )
    }

    /// Four-photo 2×2 comparison fixture.
    static func fourUpComparison() -> WorkspacePresentation {
        let photos = [
            asset(name: "DSC03001.ARW", aspect: 3.0 / 2.0),
            asset(name: "DSC03002.ARW", aspect: 2.0 / 3.0),
            asset(name: "DSC03003.ARW", aspect: 3.0 / 2.0),
            asset(name: "DSC03004.ARW", aspect: 3.0 / 2.0),
        ]
        return WorkspacePresentation(
            shootTitle: "Death Valley",
            lens: .attempts,
            groups: [
                GroupPresentation(
                    id: "four-up",
                    title: "Basin study · 4 photographs",
                    subtitle: "2:18 PM – 2:21 PM",
                    assets: photos,
                    representativeID: photos[1].id
                )
            ],
            selectedAssetID: photos[1].id,
            selectedGroupID: "four-up",
            progressCurrent: 1,
            progressTotal: 4,
            inspectorAvailable: true
        )
    }

    /// Six-photo family across two comparison pages.
    static func sixUpPaged() -> WorkspacePresentation {
        let photos = (1...6).map { asset(name: String(format: "DSC04%03d.ARW", $0), aspect: $0 % 3 == 0 ? 2.0 / 3.0 : 3.0 / 2.0) }
        return WorkspacePresentation(
            shootTitle: "Death Valley",
            lens: .attempts,
            groups: [
                GroupPresentation(
                    id: "six-up",
                    title: "Long take · 6 photographs",
                    subtitle: "2:30 PM – 2:36 PM",
                    assets: photos,
                    representativeID: photos[0].id
                )
            ],
            selectedAssetID: photos[0].id,
            selectedGroupID: "six-up",
            progressCurrent: 0,
            progressTotal: 6,
            inspectorAvailable: true
        )
    }

    static func emergingSetPreview() -> [AssetPresentation] {
        [
            asset(name: "DSC01201.ARW", aspect: 3.0 / 2.0, decision: .keep),
            asset(name: "DSC01206.ARW", aspect: 4.0 / 5.0, decision: .keep, protected: true),
            asset(name: "DSC01208.ARW", aspect: 16.0 / 9.0, decision: .keep),
        ]
    }

    static func lightWorkspace() -> WorkspacePresentation {
        let groups = lightGroups()
        return WorkspacePresentation(
            shootTitle: "Death Valley",
            lens: .light,
            groups: groups,
            selectedAssetID: groups[0].representativeID,
            selectedGroupID: groups[0].id,
            progressCurrent: 8,
            progressTotal: 31,
            inspectorAvailable: true
        )
    }

    static func mixedAspectBoard() -> WorkspacePresentation {
        WorkspacePresentation(
            shootTitle: "Mixed aspects",
            lens: .attempts,
            groups: [
                GroupPresentation(
                    id: "mixed",
                    title: "Group 1 · 5 photographs",
                    subtitle: "2:14 PM – 2:19 PM",
                    assets: Array(brooklynAssets.prefix(5)),
                    representativeID: brooklynAssets[0].id,
                    relationshipNote: nil
                )
            ],
            selectedAssetID: brooklynAssets[2].id,
            selectedGroupID: "mixed",
            progressCurrent: 3,
            progressTotal: 5,
            inspectorAvailable: true
        )
    }

    static func focusPortrait() -> WorkspacePresentation {
        var workspace = attemptWorkspace()
        let portrait = brooklynAssets[2]
        return WorkspacePresentation(
            shootTitle: workspace.shootTitle,
            lens: workspace.lens,
            groups: workspace.groups,
            selectedAssetID: portrait.id,
            selectedGroupID: workspace.selectedGroupID,
            progressCurrent: workspace.progressCurrent,
            progressTotal: workspace.progressTotal,
            inspectorAvailable: workspace.inspectorAvailable
        )
    }

    static func ungroupedWorkspace() -> WorkspacePresentation {
        WorkspacePresentation(
            shootTitle: "Empty roll",
            lens: .attempts,
            groups: [],
            selectedAssetID: nil,
            selectedGroupID: nil,
            progressCurrent: 0,
            progressTotal: 0,
            inspectorAvailable: false
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
        let ridge = Array(brooklynAssets.prefix(5))
        let panorama = Array(brooklynAssets.suffix(3))
        return [
            GroupPresentation(
                id: "attempt-ridge",
                title: "Ridge study · 6 photographs",
                subtitle: "2:14 PM – 2:16 PM",
                assets: ridge,
                representativeID: ridge.first?.id,
                relationshipNote: nil
            ),
            GroupPresentation(
                id: "attempt-panorama",
                title: "Valley panorama · 4 photographs",
                subtitle: "2:22 PM – 2:28 PM",
                assets: panorama,
                representativeID: panorama.first?.id,
                relationshipNote: nil
            ),
        ]
    }

    private static func lightGroups() -> [GroupPresentation] {
        let openShade = Array(brooklynAssets.prefix(4))
        let blueHour = Array(brooklynAssets.suffix(4))
        return [
            GroupPresentation(
                id: "light-open",
                title: "Open shade · 4 photographs",
                subtitle: "2:10 PM – 2:18 PM",
                assets: openShade,
                representativeID: openShade.first?.id,
                relationshipNote: nil
            ),
            GroupPresentation(
                id: "light-blue",
                title: "Blue hour · 4 photographs",
                subtitle: "7:41 PM – 7:53 PM",
                assets: blueHour,
                representativeID: blueHour.first?.id,
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
