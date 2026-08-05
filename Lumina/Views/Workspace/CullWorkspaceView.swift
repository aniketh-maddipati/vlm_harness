import SwiftUI

/// Stack-table workspace — scrolling rows + trailing develop pane.
struct CullWorkspaceView: View {
    let presentation: WorkspacePresentation
    var projectName: String?
    var baseRecipe: DevelopRecipe = .neutral
    @Binding var developOffsets: DevelopAdjustments
    var stackPreviewMix: Double = 1
    var revealToken: Int = 0
    var onDevelopChange: (DevelopAdjustments) -> Void = { _ in }
    var onSelectGroup: (String) -> Void
    var onSelectLead: (String, AssetID) -> Void
    var onLensChange: (WorkspaceLens) -> Void
    var onDecision: (AssetDecision, AssetID, String) -> Void
    var onApplyToRest: (String) -> Void
    var onPreviewEdits: () -> Void
    var onHome: () -> Void
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rowsRevealed = false

    private var activeGroup: GroupPresentation? {
        presentation.groups.first { $0.id == presentation.selectedGroupID }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                WorkspaceToolbar(
                    title: presentation.shootTitle,
                    lens: presentation.lens,
                    progressLabel: presentation.progressLabel,
                    onLensChange: onLensChange,
                    onHome: onHome,
                    onFinish: onFinish
                )

                categoryLegend

                if presentation.groups.isEmpty {
                    emptyState
                } else {
                    stackTable
                }

                if let activeGroup, let leadID = resolvedLeadID(for: activeGroup),
                   let lead = activeGroup.assets.first(where: { $0.id == leadID }) {
                    WorkspaceCommandBar(
                        leadDecision: lead.decision,
                        restCount: restApplyCount(for: activeGroup),
                        onKeep: { onDecision(.keep, leadID, activeGroup.id) },
                        onCut: { onDecision(.cut, leadID, activeGroup.id) },
                        onMaybe: { onDecision(.needsMe, leadID, activeGroup.id) },
                        onApplyToRest: { onApplyToRest(activeGroup.id) },
                        onPreviewEdits: onPreviewEdits
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let lead = activeLeadAsset {
                DevelopSidePane(
                    asset: lead,
                    projectName: projectName,
                    baseRecipe: baseRecipe,
                    offsets: Binding(
                        get: { developOffsets },
                        set: { newValue in
                            developOffsets = newValue
                            onDevelopChange(newValue)
                        }
                    ),
                    previewMix: stackPreviewMix
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.rail)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(presentation.lens.title) stack table")
        .onAppear { triggerRowReveal() }
        .onChange(of: revealToken) { _, _ in triggerRowReveal() }
        .onChange(of: presentation.lens) { _, _ in triggerRowReveal() }
    }

    private var activeLeadAsset: AssetPresentation? {
        guard let activeGroup else { return nil }
        guard let leadID = resolvedLeadID(for: activeGroup) else { return nil }
        return activeGroup.assets.first { $0.id == leadID }
    }

    private var categoryLegend: some View {
        HStack(spacing: LuminaTokens.Spacing.md) {
            Text("\(presentation.lens.title) stacks")
                .font(LuminaTokens.Typeface.navigation(15))
                .foregroundStyle(LuminaTokens.Ink.primary)
            Text("·")
                .foregroundStyle(LuminaTokens.Ink.tertiary)
            Text("Pick the best frame — Keep or Cut, then ⌘↩ to clear duplicates")
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text("\(presentation.groups.count) rows")
                .font(LuminaTokens.Typeface.count(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
        }
        .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
        .padding(.vertical, LuminaTokens.Spacing.sm)
        .background(LuminaTokens.Surface.porcelain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }

    private var stackTable: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LuminaTokens.Spacing.xl) {
                    ForEach(Array(presentation.groups.enumerated()), id: \.element.id) { index, group in
                        PhotoStackRow(
                            group: group,
                            isActive: group.id == presentation.selectedGroupID,
                            leadID: resolvedLeadID(for: group),
                            projectName: projectName,
                            baseRecipe: baseRecipe,
                            developOffsets: group.id == presentation.selectedGroupID ? developOffsets : .zero,
                            stackPreviewMix: group.id == presentation.selectedGroupID ? stackPreviewMix : 1,
                            revealDelay: Double(index) * 0.045,
                            isRevealed: rowsRevealed,
                            onSelect: { onSelectGroup(group.id) },
                            onSelectLead: { onSelectLead(group.id, $0) }
                        )
                        .id(group.id)
                    }
                }
                .padding(.horizontal, LuminaTokens.Spacing.workspaceMargin)
                .padding(.top, LuminaTokens.Spacing.lg)
                .padding(.bottom, LuminaTokens.Spacing.xxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LuminaTokens.Surface.porcelain)
            .onChange(of: presentation.selectedGroupID) { _, new in
                guard let new else { return }
                withAnimation(reduceMotion ? nil : LuminaTokens.Motion.selection) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: LuminaTokens.Spacing.md) {
            Text("No photographs yet")
                .font(LuminaTokens.Typeface.editorial(22))
                .foregroundStyle(LuminaTokens.Ink.secondary)
            Text("Open a shoot to begin culling.")
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Surface.porcelain)
    }

    private func triggerRowReveal() {
        rowsRevealed = false
        guard !reduceMotion else {
            rowsRevealed = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            withAnimation(LuminaTokens.Motion.reveal) {
                rowsRevealed = true
            }
        }
    }

    private func resolvedLeadID(for group: GroupPresentation) -> AssetID? {
        if group.id == presentation.selectedGroupID,
           let selected = presentation.selectedAssetID,
           group.assets.contains(where: { $0.id == selected }) {
            return selected
        }
        return group.assets
            .filter { $0.decision == .undecided }
            .max(by: { $0.qualityScore < $1.qualityScore })?.id
            ?? group.leadAsset?.id
    }

    private func restApplyCount(for group: GroupPresentation) -> Int {
        guard let leadID = resolvedLeadID(for: group),
              let lead = group.assets.first(where: { $0.id == leadID }) else {
            return group.assets.filter { $0.decision == .undecided }.count
        }
        switch lead.decision {
        case .keep:
            return group.assets.filter {
                $0.id != leadID && $0.decision == .undecided && $0.qualityScore < lead.qualityScore - 0.04
            }.count
        case .cut:
            return group.assets.filter { $0.id != leadID && $0.decision == .undecided }.count
        case .needsMe, .undecided, .anchor:
            return 0
        }
    }
}

// MARK: - Stack row

private struct PhotoStackRow: View {
    let group: GroupPresentation
    let isActive: Bool
    let leadID: AssetID?
    var projectName: String?
    var baseRecipe: DevelopRecipe = .neutral
    var developOffsets: DevelopAdjustments = .zero
    var stackPreviewMix: Double = 1
    var revealDelay: Double = 0
    var isRevealed: Bool = true
    let onSelect: () -> Void
    let onSelectLead: (AssetID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stackCards: [AssetPresentation] {
        group.stackOrdered(leadID: leadID)
    }

    /// Split long stacks into scroll lanes so cards don't bunch.
    private var lanes: [[AssetPresentation]] {
        let maxPerLane = isActive ? 4 : 5
        guard stackCards.count > maxPerLane else { return [stackCards] }
        return stride(from: 0, to: stackCards.count, by: maxPerLane).map { start in
            Array(stackCards[start..<min(start + maxPerLane, stackCards.count)])
        }
    }

    private var cardHeight: CGFloat { isActive ? 220 : 140 }
    private var leadWidth: CGFloat { isActive ? 280 : 180 }

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
            rowHeader

            VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
                ForEach(Array(lanes.enumerated()), id: \.offset) { laneIndex, lane in
                    laneScroll(lane: lane, laneIndex: laneIndex)
                }
            }

            if let note = group.relationshipNote, isActive {
                Text(note)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
        }
        .padding(LuminaTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? LuminaTokens.Surface.highlight : LuminaTokens.Surface.rail)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isActive ? LuminaTokens.Line.emphasis : LuminaTokens.Line.hairline,
                    lineWidth: isActive ? 1 : LuminaTokens.Line.hairlineWidth
                )
        }
        .opacity(rowOpacity)
        .offset(y: rowOffset)
        .animation(
            reduceMotion ? nil : LuminaTokens.Motion.reveal.delay(revealDelay),
            value: isRevealed
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .contain)
    }

    private var rowOpacity: Double {
        isRevealed ? 1 : 0
    }

    private var rowOffset: CGFloat {
        isRevealed ? 0 : 10
    }

    private func laneScroll(lane: [AssetPresentation], laneIndex: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: lane.count > 3) {
                HStack(alignment: .bottom, spacing: LuminaTokens.Spacing.md) {
                    ForEach(lane) { asset in
                        let isLead = asset.id == leadID
                        let width = isLead ? leadWidth : max(leadWidth * 0.72, 120)

                        Button {
                            onSelect()
                            onSelectLead(asset.id)
                        } label: {
                            GradedPhotoView(
                                asset: asset,
                                projectName: isActive ? projectName : nil,
                                baseRecipe: isActive ? baseRecipe : .neutral,
                                developOffsets: isActive ? developOffsets : .zero,
                                previewMix: isActive ? stackPreviewMix : 1,
                                contentMode: .fit,
                                showDecisionBadge: !isLead,
                                isSelected: isLead,
                                isLead: isLead,
                                maxPixelSize: isLead ? 1600 : 800
                            )
                            .frame(width: width, height: isLead ? cardHeight : cardHeight * 0.88)
                        }
                        .buttonStyle(LuminaCommandPressStyle())
                        .id(asset.id)
                    }
                }
                .padding(.vertical, LuminaTokens.Spacing.xs)
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight + LuminaTokens.Spacing.sm)
            .onAppear {
                scrollLeadIntoView(proxy: proxy, lane: lane)
            }
            .onChange(of: leadID) { _, _ in
                scrollLeadIntoView(proxy: proxy, lane: lane)
            }
        }
    }

    private func scrollLeadIntoView(proxy: ScrollViewProxy, lane: [AssetPresentation]) {
        guard let leadID, lane.contains(where: { $0.id == leadID }) else { return }
        withAnimation(LuminaTokens.Motion.selection) {
            proxy.scrollTo(leadID, anchor: .trailing)
        }
    }

    private var rowHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(group.rowCategory.label.uppercased())
                .font(LuminaTokens.Typeface.meta(10))
                .tracking(0.6)
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(LuminaTokens.Surface.well)

            Text(group.title)
                .font(LuminaTokens.Typeface.groupHeading(20))
                .tracking(LuminaTokens.Typeface.groupHeadingTracking)
                .foregroundStyle(LuminaTokens.Ink.strongSecondary)
                .lineLimit(2)

            if let subtitle = group.subtitle {
                Text("·")
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                Text(subtitle)
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(group.assets.count - group.undecidedCount)/\(group.assets.count)")
                .font(LuminaTokens.Typeface.count(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
        }
    }
}

#Preview("Stack table") {
    CullWorkspaceView(
        presentation: PresentationFixtures.attemptWorkspace(),
        developOffsets: .constant(.zero),
        onSelectGroup: { _ in },
        onSelectLead: { _, _ in },
        onLensChange: { _ in },
        onDecision: { _, _, _ in },
        onApplyToRest: { _ in },
        onPreviewEdits: {},
        onHome: {},
        onFinish: {}
    )
    .frame(width: 1280, height: 820)
}
