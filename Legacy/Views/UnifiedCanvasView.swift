// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import SwiftUI

/// Legacy session host retained for Phase 2 backend continuity.
/// The Phase 1 product shell (`LuminaShellView`) is the primary presentation path.
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
            LuminaTokens.Surface.porcelain.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                Text("Lumina")
                    .font(LuminaTokens.Typeface.brand(52))
                    .foregroundStyle(LuminaTokens.Ink.primary)
                Text("Every time you shoot, Lumina helps you finish something.")
                    .font(LuminaTokens.Typeface.control(16))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Spacer()
            }
            .padding(.bottom, 120)
        }
    }
}
