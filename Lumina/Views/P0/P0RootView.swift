import SwiftUI
import UniformTypeIdentifiers

/// P0 product root — Open a shoot + contact-sheet workspace.
struct P0RootView: View {
    @State private var session = P0SessionModel()
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            switch session.route {
            case .open:
                P0OpenView(session: session)
            case .time, .focus:
                ElasticRootView(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .p0KeyRouting(session: session)
        .uiTestStateProbe(session)
        #if DEBUG
        .workbenchBoot(session: session)
        .workbenchHot()
        #endif
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { session.isDropTargeted },
            set: { session.isDropTargeted = $0 }
        )) { providers in
            return session.handleDrop(providers: providers)
        }
        .overlay {
            if isDropTargeted {
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
            session.chooseFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .luminaGoHome)) { _ in
            session.goHome()
        }
    }
}
