import SwiftUI

/// One stable session stage. Posture and lenses rearrange content without replacing the host.
struct UnifiedCanvasView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        Group {
            if model.project == nil || model.totalCount == 0, !model.isImporting {
                emptyPrompt
            } else {
                DerivedSessionView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Import a shoot to begin")
                .font(.title2.weight(.semibold))
            Text("RAW folder + optional edited JPGs for taste. Review one canvas, then audit the model's shakiest calls.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
