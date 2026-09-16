import SwiftUI
import UniformTypeIdentifiers

/// Surface 1 — open a folder, or continue a shoot. Large sets carry more weight
/// than small ones; the last-opened shoot sits first.
struct P0OpenView: View {
    @Bindable var session: P0SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var arrangement: OpenShootArrangement.Result {
        OpenShootArrangement.arrange(session.recentShoots)
    }

    var body: some View {
        ZStack {
            LuminaTokens.Surface.mist.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: LuminaTokens.Spacing.xxl) {
                        hero
                        if arrangement.resume != nil || !arrangement.largerSets.isEmpty || !arrangement.smaller.isEmpty {
                            shoots
                        }
                    }
                    .padding(.horizontal, LuminaTokens.Spacing.xxl)
                    .padding(.vertical, LuminaTokens.Spacing.xl)
                    .frame(maxWidth: 1120, alignment: .leading)
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
        .padding(.horizontal, LuminaTokens.Spacing.xxl)
        .frame(height: LuminaTokens.HitTarget.header)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.lg) {
            Text("Open a shoot")
                .font(LuminaTokens.Typeface.editorial(40))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .accessibilityIdentifier("open-hero-title")

            Text(CopyContract.dropPhotographsOrFolder)
                .font(LuminaTokens.Typeface.body(18))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .lineSpacing(LuminaTokens.Typeface.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)

            Text(CopyContract.nothingLeavesMac)
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.tertiary)

            Button(action: { session.chooseFolder() }) {
                VStack(spacing: 8) {
                    Text("Open a folder")
                        .font(LuminaTokens.Typeface.editorial(22))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                    Text("or drop one on this window")
                        .font(LuminaTokens.Typeface.meta(13))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 120)
                .background(LuminaTokens.Surface.porcelain)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(LuminaTokens.Ink.primary.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(LuminaQuietButtonStyle())
            .accessibilityIdentifier(P0AccessibilityID.openChooseFolder)
            .accessibilityLabel("Open a folder")
        }
        .padding(.top, LuminaTokens.Spacing.md)
    }

    private var shoots: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.section) {
            if let resume = arrangement.resume {
                shootBand(title: "Continue") {
                    OpenShootPlate(shoot: resume, weight: .resume) {
                        session.openRecent(resume)
                    }
                }
            }

            if !arrangement.largerSets.isEmpty {
                shootBand(title: "Larger sets") {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: ChapterPack.spacing),
                            GridItem(.flexible(), spacing: ChapterPack.spacing),
                        ],
                        spacing: ChapterPack.spacing
                    ) {
                        ForEach(arrangement.largerSets) { shoot in
                            OpenShootPlate(shoot: shoot, weight: .larger) {
                                session.openRecent(shoot)
                            }
                        }
                    }
                }
            }

            if !arrangement.smaller.isEmpty {
                shootBand(title: nil) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                        ],
                        spacing: 16
                    ) {
                        ForEach(arrangement.smaller) { shoot in
                            OpenShootPlate(shoot: shoot, weight: .smaller) {
                                session.openRecent(shoot)
                            }
                        }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : LuminaTokens.Motion.reveal, value: session.recentShoots.map(\.id))
    }

    private func shootBand(title: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            if let title {
                Text(title)
                    .font(LuminaTokens.Typeface.meta(13, weight: .medium))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            content()
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
}

private struct OpenShootPlate: View {
    enum Weight {
        case resume
        case larger
        case smaller
    }

    let shoot: RecentShootSummary
    let weight: Weight
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: weight == .smaller ? 6 : 10) {
                Text(shoot.name)
                    .font(titleFont)
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    Text(subtitle)
                        .font(LuminaTokens.Typeface.meta(weight == .resume ? 13 : 12))
                        .foregroundStyle(LuminaTokens.Ink.tertiary)
                    Spacer(minLength: 8)
                    Text("\(shoot.assetCount)")
                        .font(countFont)
                        .foregroundStyle(weight == .smaller ? LuminaTokens.Ink.tertiary : LuminaTokens.Ink.primary)
                        .monospacedDigit()
                }
            }
            .padding(weight == .smaller ? 12 : LuminaTokens.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(LuminaPlatePressStyle())
        .accessibilityIdentifier(P0AccessibilityID.recentShoot(shoot.name))
        .accessibilityLabel("\(shoot.name), \(shoot.assetCount) photographs")
    }

    private var titleFont: Font {
        switch weight {
        case .resume: LuminaTokens.Typeface.editorial(26)
        case .larger: LuminaTokens.Typeface.editorial(22)
        case .smaller: LuminaTokens.Typeface.editorial(17)
        }
    }

    private var countFont: Font {
        switch weight {
        case .resume: LuminaTokens.Typeface.editorial(28)
        case .larger: LuminaTokens.Typeface.editorial(22)
        case .smaller: LuminaTokens.Typeface.meta(15)
        }
    }

    private var minHeight: CGFloat {
        switch weight {
        case .resume: 168
        case .larger: 140
        case .smaller: 88
        }
    }

    private var fill: Color {
        switch weight {
        case .resume, .larger: LuminaTokens.Surface.porcelain
        case .smaller: LuminaTokens.Surface.well.opacity(0.55)
        }
    }

    private var subtitle: String {
        switch weight {
        case .resume:
            var parts = ["as you left it"]
            if shoot.keepCount > 0 { parts.append("\(shoot.keepCount) kept") }
            return parts.joined(separator: " · ")
        case .larger, .smaller:
            if shoot.keepCount > 0 {
                return "\(shoot.keepCount) kept"
            }
            return "photographs"
        }
    }
}
