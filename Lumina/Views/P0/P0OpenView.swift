import SwiftUI
import UniformTypeIdentifiers

/// Surface 1 — choose a folder, drop a folder, or reopen a recent shoot.
struct P0OpenView: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        ZStack {
            LuminaTokens.Surface.mist.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: LuminaTokens.Spacing.section) {
                        hero
                        if !session.recentShoots.isEmpty {
                            recentSection
                        }
                    }
                    .padding(.horizontal, LuminaTokens.Spacing.xl)
                    .padding(.vertical, LuminaTokens.Spacing.lg)
                    .frame(maxWidth: 880, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }

            if session.isDropTargeted {
                dropOverlay
            }
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { session.isDropTargeted },
            set: { session.isDropTargeted = $0 }
        )) { providers in
            session.handleDrop(providers: providers)
        }
        #if DEBUG
        .workbenchHot()
        #endif
        .alert("Could not open", isPresented: Binding(
            get: { session.userFacingError != nil },
            set: { if !$0 { session.userFacingError = nil } }
        )) {
            Button("OK", role: .cancel) { session.userFacingError = nil }
        } message: {
            Text(session.userFacingError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("Lumina")
                .font(LuminaTokens.Typeface.brand(28))
                .foregroundStyle(LuminaTokens.Ink.primary)
            Spacer()
            Button("Legacy shell") {
                session.showLegacyShell = true
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .help("Open the previous Workbench shell (preserved until P0 is proven)")
        }
        .padding(.horizontal, LuminaTokens.Spacing.xl)
        .frame(height: LuminaTokens.HitTarget.header)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.lg) {
            Text("Choose a folder")
                .font(LuminaTokens.Typeface.editorial(36))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .accessibilityIdentifier("open-hero-title")

            Text(CopyContract.dropPhotographsOrFolder)
                .font(LuminaTokens.Typeface.body(17))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .lineSpacing(LuminaTokens.Typeface.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)

            Text(CopyContract.nothingLeavesMac)
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)

            HStack(spacing: LuminaTokens.Spacing.md) {
                LuminaTextActionButton(title: "Choose a folder", prominent: true) {
                    session.chooseFolder()
                }
                .accessibilityIdentifier(P0AccessibilityID.openChooseFolder)
                Text("or drop a folder anywhere in this window")
                    .font(LuminaTokens.Typeface.meta(13))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(LuminaTokens.Line.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .background(LuminaTokens.Surface.porcelain.opacity(0.5))
                .frame(height: 120)
                .overlay {
                    Text("Drop the folder")
                        .font(LuminaTokens.Typeface.meta(13))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                }
                .onTapGesture { session.chooseFolder() }
        }
        .padding(.top, LuminaTokens.Spacing.md)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
            Text("Recent shoots")
                .font(LuminaTokens.Typeface.navigation(15, weight: .medium))
                .foregroundStyle(LuminaTokens.Ink.secondary)

            VStack(spacing: 0) {
                ForEach(session.recentShoots.prefix(12)) { shoot in
                    Button {
                        session.openRecent(shoot)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(shoot.name)
                                    .font(LuminaTokens.Typeface.editorial(20))
                                    .foregroundStyle(LuminaTokens.Ink.primary)
                                Text(recentSubtitle(shoot))
                                    .font(LuminaTokens.Typeface.meta(12))
                                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundStyle(LuminaTokens.Ink.tertiary)
                        }
                        .padding(.vertical, LuminaTokens.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                    .accessibilityIdentifier(P0AccessibilityID.recentShoot(shoot.name))

                    Rectangle()
                        .fill(LuminaTokens.Line.hairline)
                        .frame(height: LuminaTokens.Line.hairlineWidth)
                }
            }
        }
    }

    private var dropOverlay: some View {
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

    private func recentSubtitle(_ shoot: RecentShootSummary) -> String {
        var parts = ["\(shoot.assetCount) photos"]
        if shoot.keepCount > 0 { parts.append("\(shoot.keepCount) kept") }
        if let path = shoot.rawFolderPath {
            parts.append((path as NSString).lastPathComponent)
        }
        return parts.joined(separator: " · ")
    }
}
