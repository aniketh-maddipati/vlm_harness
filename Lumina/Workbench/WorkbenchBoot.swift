#if DEBUG
import AppKit
import SwiftUI

/// Boots a polish session straight into photographs and applies the deep-link.
///
/// The whole point of Gate 2: an operator names a surface on the command line and the app is
/// already showing it — no Open picker, no ingest flow, no sample data. It opens the cut latency
/// card through the *real* `openFolder` path, so what is polished is what ships.
///
/// Failure follows D35 rather than the shipping Open surface's alert: a missing card leaves the
/// app alive with a facts-chip naming the exact path it tried. Never a modal, never a crash.
struct WorkbenchBootModifier: ViewModifier {
    let session: P0SessionModel
    let plan: WorkbenchBootPlan

    @State private var openRequested = false
    @State private var deepLinkApplied = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                bootNote.padding(16)
            }
            .onAppear(perform: openCard)
            // The card streams in; the deep-link can only be applied once rows exist.
            .onChange(of: session.visibleItems.count) { _, _ in applyDeepLink() }
            // Launch-to-photographs stops when a preview is actually on screen — not when the
            // window appears, and not when the file list is merely known.
            .onChange(of: session.status.previewReadyCount) { _, count in
                if count >= 1 { WorkbenchLaunchClock.recordPhotographsVisible() }
            }
            .onChange(of: session.status.phaseDetail) { _, phase in
                WorkbenchTrace.log(
                    "phase=\(phase) discovered=\(session.status.discoveredCount) "
                        + "assets=\(session.status.assetCount) previews=\(session.status.previewReadyCount)"
                )
            }
    }

    // MARK: - Boot

    private func openCard() {
        WorkbenchTrace.log("onAppear cardExists=\(plan.cardExists) openRequested=\(openRequested)")
        guard plan.cardExists, !openRequested else { return }
        openRequested = true
        session.openFolder(plan.card)
        WorkbenchTrace.log("openFolder(\(plan.card.path)) requested")
    }

    private func applyDeepLink() {
        guard plan.cardExists, !deepLinkApplied else { return }
        let items = session.visibleItems
        guard !items.isEmpty else { return }

        let columns = max(session.densityColumns, 1)
        let rowIndex = max((plan.link.row ?? 1) - 1, 0)
        let firstIndexOfRow = rowIndex * columns

        // A `--row 40` against a still-streaming card must land on row 40, not on whichever row
        // happened to arrive first. Wait for the named row, or for discovery to finish — after
        // which the row simply does not exist and we clamp to the last one.
        let discoveryFinished = session.status.discoveredCount > 0
            && session.status.assetCount >= session.status.discoveredCount
        guard firstIndexOfRow < items.count || discoveryFinished else { return }

        deepLinkApplied = true
        let assetIndex = min(firstIndexOfRow, items.count - 1)

        let totalRows = max(Int(ceil(Double(items.count) / Double(columns))), 1)
        session.setScrollAnchor(Double(rowIndex) / Double(max(totalRows - 1, 1)))

        if plan.link.focused || plan.link.surface != .table {
            session.setFocus(items[assetIndex].id)
        }
        switch plan.link.surface {
        case .table:
            // The deep-link owns the surface. The app restores the last session — including an
            // open single-photo editor — so `--surface table` must actively close it, or a
            // polish session lands on whatever the previous one happened to leave behind.
            session.inspectingAssetID = nil
        case .frame, .loupe:
            // `loupe` has no referent in P0; `WorkbenchLaunch` already recorded that in
            // `unresolved` and it lands on the frame rather than inventing a surface.
            session.openFocusedPhotograph()
        }

        WorkbenchTrace.log(
            "deep-link applied surface=\(plan.link.surface.rawValue) "
                + "row=\(plan.link.row.map(String.init) ?? "1") assetIndex=\(assetIndex) "
                + "of=\(items.count) focused=\(session.focusedAssetID != nil) "
                + "inspecting=\(session.inspectingAssetID != nil) "
                + "unresolved=\(plan.unresolved.count)"
        )
    }

    // MARK: - Facts chip (D35)

    @ViewBuilder
    private var bootNote: some View {
        if !plan.cardExists {
            RecoveryFactsChip(
                headline: "Fixture card not found",
                detail: "\(plan.card.path)\nSet FIXTURE_ROOT, or cut the card first.",
                actionTitle: "Copy cut command"
            ) {
                copyToPasteboard(
                    "python3 Scripts/fixtures/cut_latency_card.py --card \(plan.link.card)"
                )
            }
            .frame(maxWidth: 420)
        } else if !plan.unresolved.isEmpty {
            RecoveryFactsChip(
                headline: "Deep-link partly unresolved",
                detail: plan.unresolved.joined(separator: "\n"),
                actionTitle: "Copy notes"
            ) {
                copyToPasteboard(plan.unresolved.joined(separator: "\n"))
            }
            .frame(maxWidth: 420)
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

extension View {
    /// Applies the workbench boot when this launch asked for one; otherwise changes nothing.
    @ViewBuilder
    func workbenchBoot(session: P0SessionModel) -> some View {
        if let plan = WorkbenchLaunch.boot {
            modifier(WorkbenchBootModifier(session: session, plan: plan))
        } else {
            self
        }
    }
}
#endif
