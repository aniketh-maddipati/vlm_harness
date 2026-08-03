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
        ZStack {
            LuminaAtmosphereBackdrop()

            VStack(spacing: 18) {
                Spacer()
                Text("Lumina")
                    .font(LuminaAtmosphere.Typeface.brand(52))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text("Drop a shoot. Keep only what needs you.")
                    .font(LuminaAtmosphere.Typeface.body(16))
                    .foregroundStyle(LuminaAtmosphere.whisper)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Spacer()
            }
            .padding(.bottom, 120)
        }
    }
}
