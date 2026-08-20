import SwiftUI

/// Explicit legacy Workbench door (D38) — models are constructed only after the user opens this surface.
struct P0LegacyShellContainer: View {
    @Bindable var session: P0SessionModel
    @State private var legacyModel: ProjectViewModel?
    @State private var legacyShell: LuminaShellModel?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let legacyModel, let legacyShell {
                    ContentViewLegacyHost(model: legacyModel, shell: legacyShell)
                } else {
                    LuminaTokens.Surface.mist
                        .ignoresSafeArea()
                }
            }
            .onAppear(perform: ensureLegacyShellConstructed)
            .onChange(of: session.showLegacyShell) { _, isShowing in
                if isShowing { ensureLegacyShellConstructed() }
            }

            Button("P0 contact sheet") {
                session.showLegacyShell = false
                session.refreshRecent()
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .padding(16)
        }
        .onReceive(NotificationCenter.default.publisher(for: .luminaImportRAW)) { _ in
            guard session.showLegacyShell else { return }
            ensureLegacyShellConstructed()
            legacyModel?.pickRAWFolder()
        }
    }

    private func ensureLegacyShellConstructed() {
        guard legacyModel == nil else { return }
        legacyModel = ProjectViewModel()
        legacyShell = LuminaShellModel()
    }
}

/// Hosts the preserved pre-P0 shell without wiring legacy models into the default launch path.
struct ContentViewLegacyHost: View {
    @Bindable var model: ProjectViewModel
    @Bindable var shell: LuminaShellModel

    var body: some View {
        ZStack {
            LuminaShellView(model: model, shell: shell)
            if model.isImporting {
                ImportLoadingView(
                    progress: model.importProgress,
                    photos: model.importPreviewPhotos,
                    isFinishing: model.importFinishing
                )
            }
        }
    }
}
