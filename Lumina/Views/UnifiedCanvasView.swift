import SwiftUI

/// Single agent canvas — morphs between stack feed, set review, keeps browse, and session summary.
struct UnifiedCanvasView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        Group {
            switch model.appSpine {
            case .stackFeed:
                stackFeedContent
            case .reviewingSet:
                ClusterCullView(model: model)
            case .sessionComplete:
                SessionDoneView(model: model)
            case .browsingKeeps:
                KeepsBrowserView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.38), value: model.appSpine)
    }

    @ViewBuilder
    private var stackFeedContent: some View {
        if model.project == nil || model.totalCount == 0, !model.isImporting {
            emptyIngestPrompt
        } else {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your sets")
                            .font(.title2.weight(.semibold))
                        Text(model.agentPlanText.isEmpty ? "Review each stack · S keep · A reject" : model.agentPlanText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.decisionBudgetText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(model.uncertainCount > 0 ? .orange : .secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                StackFeedView(model: model, clusters: model.reviewClusters)
            }
        }
    }

    private var emptyIngestPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "sdcard")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Insert SD card, iPhone, or external drive")
                .font(.title2.weight(.semibold))
            Text("Drop iCloud folders or local shoots here. Lumina downloads cloud files and uses full-resolution JPG/HEIC — not tiny placeholders.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Text("Sidebar: iCloud… · Scan drives · ⌘I manual")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
