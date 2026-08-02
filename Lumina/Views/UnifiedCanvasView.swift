import SwiftUI

/// Single canvas — linear session spine with optional grid overview lens.
struct UnifiedCanvasView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        ZStack {
            if model.project == nil || model.totalCount == 0, !model.isImporting {
                emptyPrompt
            } else if model.showGridOverview {
                GridOverviewView(model: model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                SessionSpineView(model: model)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.35), value: model.sessionPhase)
        .animation(.easeInOut(duration: 0.35), value: model.showGridOverview)
    }

    private var emptyPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Import a shoot to begin")
                .font(.title2.weight(.semibold))
            Text("RAW folder + optional edited JPGs for taste. You'll move through Meet → Pick → Decide → Export.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
