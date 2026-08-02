import SwiftUI

/// Context-aware bottom panel for the linear session spine.
struct AdaptivePanelHost: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        Group {
            if model.showGridOverview {
                HStack {
                    Text("Grid lens · sort and filter keeps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Esc to return")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                switch model.sessionPhase {
                case .meet:
                    HStack {
                        Text(model.decisionBudgetText)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("Return to pick · ]/[ jump sets")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                case .pick:
                    HStack {
                        Text("\(model.manualPickIDs.count) selected")
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                        Text("Tap cards · Return to confirm")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                case .decide:
                    HStack {
                        Text("Taste-applied preview")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("P/X · M flag · Space before/after")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                case .export:
                    HStack {
                        Text("Session clear · \(model.keepCount) keeps · export?")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button("Grid") { model.openGridOverview() }
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
