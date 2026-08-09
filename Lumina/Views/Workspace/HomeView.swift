import SwiftUI

struct HomeView: View {
    let presentation: HomePresentation
    var onOpenNew: () -> Void
    var onContinue: () -> Void
    var onOpenFinished: (String) -> Void
    var onOpenSettings: () -> Void
    var onOpenShoot: () -> Void
    var onScanBacklog: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LuminaTokens.Spacing.section) {
                header
                contentSections
            }
            .padding(.horizontal, LuminaTokens.Spacing.xl)
            .padding(.vertical, LuminaTokens.Spacing.lg)
            .frame(maxWidth: 960, alignment: .leading)
            // Center the reading column — never pinned to the left corner on wide displays.
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LuminaTokens.Surface.porcelain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Home")
    }

    @ViewBuilder
    private var contentSections: some View {
        if let newSection = presentation.newSection {
            homeSection(title: newSection.headline) {
                VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
                    Text(newSection.detail)
                        .font(LuminaTokens.Typeface.control(14))
                        .foregroundStyle(LuminaTokens.Ink.secondary)
                    HomeShootCard(card: newSection.card, actionTitle: newSection.actionTitle, onAction: onOpenNew)
                }
            }
        }

        if let continueSection = presentation.continueSection {
            homeSection(title: "Continue") {
                HomeShootCard(card: continueSection, actionTitle: continueSection.primaryActionTitle, onAction: onContinue)
            }
        } else if presentation.newSection == nil && presentation.recentlyFinished.isEmpty {
            emptyState
        }

        if !presentation.recentlyFinished.isEmpty {
            homeSection(title: "Recently finished") {
                VStack(spacing: LuminaTokens.Spacing.md) {
                    ForEach(presentation.recentlyFinished) { item in
                        FinishedStripRow(item: item) {
                            onOpenFinished(item.id)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.lg) {
            HStack {
                Text("Lumina")
                    .font(LuminaTokens.Typeface.brand(28))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                LuminaGhostActionButton(title: "Settings", action: onOpenSettings)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
                    Text(presentation.greeting)
                        .font(LuminaTokens.Typeface.editorial(32))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                        .lineSpacing(LuminaTokens.Typeface.bodyLineSpacing)

                    if let summary = presentation.readinessSummary {
                        Text(summary)
                            .font(LuminaTokens.Typeface.meta(13))
                            .foregroundStyle(LuminaTokens.Ink.secondary)
                    }
                }

                Spacer(minLength: LuminaTokens.Spacing.lg)

                LuminaGhostActionButton(title: "Scan backlog", action: onScanBacklog)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.lg) {
            Text("No shoots open")
                .font(LuminaTokens.Typeface.editorial(28))
                .foregroundStyle(LuminaTokens.Ink.primary)

            Text(CopyContract.dropPhotographsOrFolder)
                .font(LuminaTokens.Typeface.body(17))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .lineSpacing(LuminaTokens.Typeface.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)

            Text(CopyContract.nothingLeavesMac)
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)

            Text(CopyContract.groupingVisibleMotion)
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            LuminaTextActionButton(title: "Open shoot", prominent: true, action: onOpenShoot)
        }
        .padding(.vertical, LuminaTokens.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No shoots open. Open a shoot folder to begin.")
    }

    private func homeSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
            SectionHeader(title: title)
            content()
        }
    }
}

// MARK: - Shoot card (home)

private struct HomeShootCard: View {
    let card: ShootCardPresentation
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
            ShootCardHeader(card: card)

            if !card.previewAssets.isEmpty {
                PhotoStripPreview(assets: card.previewAssets, maxCount: 4, height: 108)
            }

            HStack {
                if let progress = card.progressLabel {
                    Text(progress)
                        .font(LuminaTokens.Typeface.meta(13))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                }
                Spacer(minLength: 12)
                LuminaTextActionButton(title: actionTitle, prominent: true, action: onAction)
            }
        }
        .padding(.vertical, LuminaTokens.Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(card.title), \(card.photographCount) photographs")
    }
}

private struct FinishedStripRow: View {
    let item: FinishedStripItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: LuminaTokens.Spacing.md) {
                PhotoStripPreview(assets: item.thumbAssets, maxCount: 4, height: 56)
                    .frame(width: 200)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(LuminaTokens.Typeface.editorial(20))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                        .lineLimit(1)
                    Text("\(item.photographCount) photographs")
                        .font(LuminaTokens.Typeface.meta(13))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(LuminaTokens.Typeface.navigation(12, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            .padding(.vertical, LuminaTokens.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
        .accessibilityLabel("\(item.title), \(item.photographCount) photographs, finished")
    }
}

// MARK: - Shared shoot card header

struct ShootCardHeader: View {
    let card: ShootCardPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.title)
                    .font(LuminaTokens.Typeface.editorial(22))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                ReadinessBadge(readiness: card.readiness)
            }

            HStack(spacing: 8) {
                if let date = card.dateLabel {
                    Text(date)
                        .font(LuminaTokens.Typeface.meta(12))
                        .foregroundStyle(LuminaTokens.Ink.secondary)
                }
                if let location = card.locationLabel {
                    if card.dateLabel != nil {
                        Text("·").foregroundStyle(LuminaTokens.Ink.tertiary)
                    }
                    Text(location)
                        .font(LuminaTokens.Typeface.meta(12))
                        .foregroundStyle(LuminaTokens.Ink.secondary)
                }
            }

            Text("\(card.photographCount) photographs")
                .font(LuminaTokens.Typeface.count(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)

            if let warning = card.boundaryWarning {
                Text(warning)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Status.needsAttention)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ReadinessBadge: View {
    let readiness: SourceReadiness

    var body: some View {
        Text(label)
            .font(LuminaTokens.Typeface.meta(10, weight: .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill)
            )
            .accessibilityLabel("Source \(label)")
    }

    private var label: String {
        switch readiness {
        case .ready: "Ready"
        case .findingMore: "Finding more"
        case .disconnected: "Disconnected"
        case .missing: "Missing"
        case .empty: "Empty"
        }
    }

    private var ink: Color {
        switch readiness {
        case .ready: LuminaTokens.Ink.secondary
        case .findingMore: LuminaTokens.Status.needsAttention
        case .disconnected, .missing: LuminaTokens.Status.reject
        case .empty: LuminaTokens.Ink.tertiary
        }
    }

    private var fill: Color {
        ink.opacity(0.10)
    }
}

#Preview("New SD card") {
    HomeView(
        presentation: PresentationFixtures.homeNewSDCard(),
        onOpenNew: {},
        onContinue: {},
        onOpenFinished: { _ in },
        onOpenSettings: {},
        onOpenShoot: {},
        onScanBacklog: {}
    )
    .frame(width: 900, height: 720)
}

#Preview("Empty") {
    HomeView(
        presentation: PresentationFixtures.homeEmpty(),
        onOpenNew: {},
        onContinue: {},
        onOpenFinished: { _ in },
        onOpenSettings: {},
        onOpenShoot: {},
        onScanBacklog: {}
    )
    .frame(width: 900, height: 600)
}
