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
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your sets")
                        .font(.title2.weight(.semibold))
                    Text(model.agentPlanText)
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
