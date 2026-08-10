import Foundation

/// Hi-fi user-visible copy — every string here must appear in `design/copy-contract.txt`.
enum CopyContract {

    // MARK: - Staged & receipt

    static let adaptedIndependently = "adapted — each RAW rendered independently"
    static let editedChip = "Edited"

    static func stagedHeader(_ snapshot: StagingCopySnapshot) -> String {
        if snapshot.excludedCount > 0 {
            let ringLabel: String = switch snapshot.ring {
            case .row: "row \(snapshot.rowIndex)"
            case .scene: "scene"
            case .shoot: "shoot"
            }
            return "STAGED · \(ringLabel) · \(snapshot.scopeCount) selected · \(snapshot.excludedCount) excluded · ⏎ applies · Esc cancels"
        }
        return "STAGED · row \(snapshot.rowIndex) · \(snapshot.laneTimestamp) · \(snapshot.scopeCount) selected · ⏎ applies · Esc cancels, nothing applied"
    }

    static func adaptBanner(_ snapshot: StagingCopySnapshot) -> String {
        if snapshot.excludedCount > 0, snapshot.ring == .shoot {
            return "Adapt → \(snapshot.scopeCount) · \(snapshot.excludedCount) excluded ⏎ · ⇧⏎ shoot"
        }
        if snapshot.ring == .scene {
            return "Adapt → \(snapshot.scopeCount) ⏎ · ⇧⏎ scene · Esc"
        }
        return "Adapt → \(snapshot.scopeCount) ⏎ · Esc"
    }

    static func developBanner(count: Int) -> String {
        "Develop → \(count) ⏎ · Esc"
    }

    static func adaptedReceipt(count: Int) -> String {
        "Adapted → \(count) · ⌘Z"
    }

    static func provenanceChip(referenceFrame: String, scopeCount: Int) -> String {
        "← \(referenceFrame) · \(scopeCount)"
    }

    // MARK: - Open

    static let nothingLeavesMac = "nothing leaves this Mac"
    static let dropPhotographsOrFolder = "drop photographs or a folder anywhere"
    static let groupingVisibleMotion = "grouping happens in front of you, in visible motion"
    static let copiesAutomatically = "copies automatically · safe to eject when ✓ appears"
    static let copyingOriginals = "copying originals · work while it copies"
    static let cullHeaderResume = "6/8 kept · 2 out · resume = first undecided frame"

    static func cullHeader(kept: Int, total: Int, out: Int) -> String {
        "\(kept)/\(total) kept · \(out) out · resume = first undecided frame"
    }

    // MARK: - Footer hints

    static let tableFooterHover = "P keep · X out · ⏎ edit · Space loupe · drag to move (hover)"
    static let tableFooterShortcuts = "P · X · arrows · ⏎ edit · ? all shortcuts"
    static let editFooterShortcuts = "A develop · Tab arms · ⌥←→ adjusts · ⏎ done, next kept · ? all shortcuts"
    static let developThisPhotograph = "Develop this photograph · A"

    // MARK: - Export

    static let exportRecipeHint = "⌥⌘E changes the recipe."

    // MARK: - Plumbing (PL — sovereignty + loupe exception)

    static let sovereigntyPlumbing = "files stay where they are · edits in open sidecars · this shoot opens in Lightroom as-is"
    static let fetchingFullRAW = "fetching full RAW"

    // MARK: - Failure headlines

    static let pointedFolderMoved = "Pointed folder moved"
    static let fileDamagedPreviewOnly = "file damaged — preview only"
    static let staleRender = "Stale render"

    static let pointedFolderMovedBody = "The folder you pointed at is no longer where it was."
    static let pointedFolderMovedAction = "Point at it again"

    static let staleRenderBody = "Latest-wins: ⌘E re-renders dirty frames only; the header counts what is current."
    static let staleRenderAction = "⌘E re-renders"
}

// MARK: - Snapshot builder (ONE count source for A1)

enum CopyContractBuilder {
    private static let laneTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func referenceFrameNumber(from filename: String?) -> String {
        guard let filename else { return "8288" }
        let digits = filename.filter(\.isNumber)
        if digits.count >= 4 { return String(digits.suffix(4)) }
        return digits.isEmpty ? "8288" : digits
    }

    static func laneTimestamp(from date: Date?) -> String {
        guard let date else { return "18:17" }
        return laneTimeFormatter.string(from: date)
    }

    static func snapshot(
        from selection: WorkbenchSelection,
        presentation: WorkspacePresentation,
        model: ProjectViewModel,
        excludedCount: Int? = nil,
        ring: PropagationRing? = nil,
        isDevelop: Bool = false
    ) -> StagingCopySnapshot? {
        if let propagation = selection.propagation, selection.staged?.isTreatStaging == true {
            let scope = propagation.resolvedScope(presentation: presentation, model: model)
            guard !scope.memberIDs.isEmpty else { return nil }
            let group = presentation.groups.first { $0.id == propagation.referenceGroupID }
            let rowIndex = (presentation.groups.firstIndex { $0.id == propagation.referenceGroupID }).map { $0 + 1 } ?? 1
            return StagingCopySnapshot(
                scopeCount: scope.memberIDs.count,
                excludedCount: excludedCount ?? scope.excludedCount,
                rowIndex: rowIndex,
                laneTimestamp: laneTimestamp(from: group?.timeStart),
                referenceFrameNumber: propagation.referenceFrame,
                ring: ring ?? propagation.ring,
                isDevelop: false
            )
        }
        guard !selection.ids.isEmpty else { return nil }
        let group = presentation.selectedGroup
        let rowIndex = (presentation.groups.firstIndex { $0.id == group?.id }).map { $0 + 1 } ?? 1
        return StagingCopySnapshot(
            scopeCount: selection.count,
            excludedCount: excludedCount ?? 0,
            rowIndex: rowIndex,
            laneTimestamp: laneTimestamp(from: group?.timeStart),
            referenceFrameNumber: referenceFrameNumber(from: group?.representative?.filename),
            ring: ring ?? .row,
            isDevelop: isDevelop
        )
    }
}
