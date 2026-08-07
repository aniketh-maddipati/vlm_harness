import SwiftUI
import UniformTypeIdentifiers

/// P0 product root — Open a shoot + contact-sheet workspace.
/// Legacy Workbench shell remains reachable until this route is proven.
struct P0RootView: View {
    @State private var session = P0SessionModel()
    @State private var legacyModel = ProjectViewModel()
    @State private var legacyShell = LuminaShellModel()
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if session.showLegacyShell {
                legacyContainer
            } else {
                switch session.route {
                case .open:
                    P0OpenView(session: session)
                case .contactSheet:
                    P0ContactSheetView(session: session)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .uiTestStateProbe(session)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard !session.showLegacyShell else { return false }
            return session.handleDrop(providers: providers)
        }
        .overlay {
            if isDropTargeted, !session.showLegacyShell {
                ZStack {
                    LuminaTokens.Status.selection.opacity(0.06)
                    RoundedRectangle(cornerRadius: LuminaTokens.Radius.panel, style: .continuous)
                        .strokeBorder(LuminaTokens.Ink.primary.opacity(0.45), lineWidth: 1.5)
                        .padding(18)
                    Text("Release to open")
                        .font(LuminaTokens.Typeface.title(28))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            session.refreshRecent()
            #if DEBUG
            // UI-test auto-open: open the seeded fixture through the real openRecent path so flows
            // don't depend on the flaky Open-surface accessibility. The manual click-through path
            // has its own dedicated test.
            if UITestSupport.isActive, UITestSupport.autoOpen, session.route == .open,
               let name = UITestSupport.fixtureName {
                // Open by name via the real openExisting path — no dependency on the recent list
                // being populated yet (that listing races on cold start).
                session.openShoot(named: name)
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .luminaImportRAW)) { _ in
            if session.showLegacyShell {
                legacyModel.pickRAWFolder()
            } else {
                session.chooseFolder()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .luminaGoHome)) { _ in
            if session.showLegacyShell {
                session.showLegacyShell = false
            }
            session.goHome()
        }
    }

    private var legacyContainer: some View {
        ZStack(alignment: .topTrailing) {
            ContentViewLegacyHost(model: legacyModel, shell: legacyShell)
            Button("P0 contact sheet") {
                session.showLegacyShell = false
                session.refreshRecent()
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .padding(16)
        }
    }
}

/// Hosts the preserved pre-P0 shell without replacing ContentView's drop/key wiring permanently.
struct ContentViewLegacyHost: View {
    @Bindable var model: ProjectViewModel
    @Bindable var shell: LuminaShellModel

    var body: some View {
        // Reuse LuminaShellView directly; import overlay behavior stays in ContentView for legacy path.
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
