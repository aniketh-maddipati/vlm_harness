import SwiftUI

/// Context-aware bottom panel — tools appear only for the current agent phase.
struct AdaptivePanelHost: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        Group {
            switch model.appSpine {
            case .stackFeed:
                HStack {
                    Text(model.decisionBudgetText)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("Tap a stack to review")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            case .reviewingSet:
                switch model.groupPhase {
                case .decide:
                    EmptyView()
                case .pick:
                    HStack {
                        Text("\(model.manualPickIDs.count) selected")
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                        Text("Tap cards to keep")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                default:
                    HStack {
                        Button("← All sets") { model.backToStackFeed() }
                            .buttonStyle(LuminaPressStyle())
                        Spacer()
                        if model.groupPhase == .intro {
                            Text("Return to open set")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            case .sessionComplete:
                if let summary = model.sessionSummary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session summary")
                            .font(.subheadline.weight(.semibold))
                        Text(summary.narrative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .browsingKeeps:
                if model.keepsBrowseLayout == .focus {
                    HStack {
                        Text("\(model.keepCount) keeps")
                            .font(.subheadline)
                        Spacer()
                        Button("← Sets") {
                            model.unfocusKeep()
                            model.appSpine = .stackFeed
                        }
                        .buttonStyle(LuminaPressStyle())
                    }
                } else {
                    HStack {
                        Text("\(model.keepCount) keeps")
                            .font(.subheadline)
                        Spacer()
                        Button("← Sets") {
                            model.unfocusKeep()
                            model.appSpine = .stackFeed
                        }
                        .buttonStyle(LuminaPressStyle())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

struct SessionSummarySheet: View {
    let summary: SessionSummary
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Session complete")
                .font(.title2.weight(.semibold))
            Text(summary.narrative)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Total"); Text("\(summary.totalPhotos)").monospacedDigit()
                }
                GridRow {
                    Text("Keeps"); Text("\(summary.keepCount)").monospacedDigit()
                }
                GridRow {
                    Text("Auto actions"); Text("\(summary.autoActions)").monospacedDigit()
                }
                GridRow {
                    Text("Your overrides"); Text("\(summary.userOverrides)").monospacedDigit()
                }
                GridRow {
                    Text("Feedback learned"); Text("\(summary.feedbackEvents)").monospacedDigit()
                }
            }
            .font(.subheadline)

            Button("Continue") { onDismiss() }
                .buttonStyle(LuminaPrimaryButtonStyle())
        }
        .padding(28)
        .frame(width: 360)
    }
}
