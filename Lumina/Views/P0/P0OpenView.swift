import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Surface 1 — open a folder, or continue a shoot. Large sets carry more weight
/// than small ones; the last-opened shoot sits first.
struct P0OpenView: View {
    @Bindable var session: P0SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var arrangement: OpenShootArrangement.Result {
        OpenShootArrangement.arrange(
            session.recentShoots,
            resumeName: session.lastOpenedShootName
        )
    }

    private var deskIsEmpty: Bool {
        arrangement.resume == nil
            && arrangement.largerSets.isEmpty
            && arrangement.smaller.isEmpty
    }

    var body: some View {
        ZStack {
            LuminaTokens.Surface.mist.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: LuminaTokens.Spacing.xxl) {
                        hero
                        if let error = session.userFacingError {
                            P0OpenFeedback(message: error) {
                                session.chooseFolder()
                            }
                        }
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
    }

    private var header: some View {
        HStack {
            Text("Lumina")
                .font(LuminaTokens.Typeface.brand(28))
                .foregroundStyle(LuminaTokens.Ink.primary)
            Spacer()
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

            if deskIsEmpty {
                openFolderTarget(tall: true)
            }
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
                    if let lead = arrangement.largerSets.first {
                        OpenShootPlate(shoot: lead, weight: .lead) {
                            session.openRecent(lead)
                        }
                    }
                    let rest = Array(arrangement.largerSets.dropFirst())
                    if !rest.isEmpty || !deskIsEmpty {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: ChapterPack.spacing),
                                GridItem(.flexible(), spacing: ChapterPack.spacing),
                            ],
                            spacing: ChapterPack.spacing
                        ) {
                            ForEach(rest) { shoot in
                                OpenShootPlate(shoot: shoot, weight: .larger) {
                                    session.openRecent(shoot)
                                }
                            }
                            if !deskIsEmpty {
                                openFolderTarget(tall: false)
                            }
                        }
                    }
                }
            } else if !deskIsEmpty {
                shootBand(title: "Larger sets") {
                    openFolderTarget(tall: false)
                }
            }

            if !arrangement.smaller.isEmpty {
                shootBand(title: "Quieter") {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: LuminaTokens.Spacing.md),
                            GridItem(.flexible(), spacing: LuminaTokens.Spacing.md),
                            GridItem(.flexible(), spacing: LuminaTokens.Spacing.md),
                        ],
                        spacing: LuminaTokens.Spacing.md
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

    private func openFolderTarget(tall: Bool) -> some View {
        let corner = HiFiTokens.Layout.recentShootCornerRadius
        let height = tall
            ? HiFiTokens.Layout.openCardMinTarget
            : HiFiTokens.Layout.recentShootLargerHeight
        return Button(action: { session.chooseFolder() }) {
            Text("Open a folder")
                .font(LuminaTokens.Typeface.editorial(tall ? 22 : 17))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .frame(maxWidth: .infinity, minHeight: height, alignment: tall ? .center : .leading)
                .padding(tall ? 0 : LuminaTokens.Spacing.md)
                .background(LuminaTokens.Surface.porcelain)
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(
                            LuminaTokens.Ink.primary.opacity(0.22),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .buttonStyle(LuminaOpenPlatePressStyle())
        .accessibilityIdentifier(P0AccessibilityID.openChooseFolder)
        .accessibilityLabel("Open a folder")
        .accessibilityHint(CopyContract.dropPhotographsOrFolder)
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
            Text(CopyContract.dropPhotographsOrFolder)
                .font(LuminaTokens.Typeface.title(28))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LuminaTokens.Spacing.xxl)
        }
        .allowsHitTesting(false)
        .accessibilityLabel(CopyContract.dropPhotographsOrFolder)
    }
}

private struct OpenShootPlate: View {
    enum Weight {
        case resume
        case lead
        case larger
        case smaller
    }

    let shoot: RecentShootSummary
    let weight: Weight
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            plateBody
            .padding(weight == .smaller ? 12 : LuminaTokens.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background {
                ZStack {
                    fill
                    if weight != .smaller, let path = shoot.coverPath ?? shoot.stillPaths.dropFirst().first ?? shoot.stillPaths.first {
                        PlateGround(path: path)
                    }
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: HiFiTokens.Layout.recentShootCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                if weight == .resume || weight == .lead {
                    RoundedRectangle(
                        cornerRadius: HiFiTokens.Layout.recentShootCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        HiFiTokens.Ring.halo.opacity(HiFiTokens.Ring.haloOpacity),
                        lineWidth: HiFiTokens.Ring.haloWidth
                    )
                }
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: HiFiTokens.Layout.recentShootCornerRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(LuminaOpenPlatePressStyle())
        .accessibilityIdentifier(P0AccessibilityID.recentShoot(shoot.name))
        .accessibilityLabel(OpenShootArrangement.plateTitle(
            name: shoot.name,
            from: shoot.capturedFrom,
            to: shoot.capturedTo
        ))
        .accessibilityValue("\(progressLine), \(dateLine.map { $0 + ", " } ?? "")\(shoot.assetCount) photographs")
        .accessibilityHint("Opens this shoot")
    }

    private var plateBody: some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            StillStrip(paths: Array(shoot.stillPaths.prefix(stillCount)), height: stillHeight)
            VStack(alignment: .leading, spacing: LuminaTokens.Spacing.xs) {
                    Text(OpenShootArrangement.plateTitle(
                        name: shoot.name,
                        from: shoot.capturedFrom,
                        to: shoot.capturedTo
                    ))
                    .font(titleFont)
                    .foregroundStyle(LuminaTokens.Ink.primary)
                    .lineLimit(2)
                    if let folderLine {
                        Text(folderLine)
                            .font(LuminaTokens.Typeface.meta(12))
                            .foregroundStyle(LuminaTokens.Ink.tertiary)
                            .lineLimit(1)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(progressLine)
                            .font(LuminaTokens.Typeface.meta(weight == .resume || weight == .lead ? 13 : 12))
                            .foregroundStyle(LuminaTokens.Ink.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(shoot.assetCount)")
                            .font(countFont)
                            .foregroundStyle(weight == .smaller ? LuminaTokens.Ink.tertiary : LuminaTokens.Ink.primary)
                            .monospacedDigit()
                    }
                    if let dateLine {
                        Text(dateLine)
                            .font(LuminaTokens.Typeface.meta(12))
                            .foregroundStyle(LuminaTokens.Ink.tertiary)
                            .lineLimit(1)
                    }
                }
        }
    }

    private var titleFont: Font {
        switch weight {
        case .resume: LuminaTokens.Typeface.editorial(26)
        case .lead: LuminaTokens.Typeface.editorial(22)
        case .larger: LuminaTokens.Typeface.editorial(18)
        case .smaller: LuminaTokens.Typeface.editorial(16)
        }
    }

    private var countFont: Font {
        switch weight {
        case .resume: LuminaTokens.Typeface.editorial(28)
        case .lead: LuminaTokens.Typeface.editorial(22)
        case .larger: LuminaTokens.Typeface.editorial(18)
        case .smaller: LuminaTokens.Typeface.meta(15)
        }
    }

    private var minHeight: CGFloat {
        switch weight {
        case .resume: 220
        case .lead: 188
        case .larger: HiFiTokens.Layout.recentShootLargerHeight
        case .smaller: 120
        }
    }

    private var fill: Color {
        switch weight {
        case .resume, .lead: LuminaTokens.Surface.porcelain
        case .larger: LuminaTokens.Surface.porcelain.opacity(0.92)
        case .smaller: LuminaTokens.Surface.well.opacity(0.55)
        }
    }

    /// The folder name, only when the title is a date because the name itself is not one.
    private var folderLine: String? {
        guard OpenShootArrangement.isOpaqueName(shoot.name) else { return nil }
        guard OpenShootArrangement.dateSpan(from: shoot.capturedFrom, to: shoot.capturedTo) != nil else { return nil }
        return shoot.name
    }

    /// Where the work stands. The date is a separate caption.
    private var progressLine: String {
        var parts: [String] = []
        if weight == .resume { parts.append("as you left it") }
        if shoot.keepCount > 0 {
            parts.append("\(shoot.keepCount) kept")
        } else if shoot.markedCount == 0 {
            parts.append("still open")
        } else {
            parts.append("none kept")
        }
        return parts.joined(separator: " · ")
    }

    /// Omitted when the title is already that date.
    private var dateLine: String? {
        guard !OpenShootArrangement.isOpaqueName(shoot.name) else { return nil }
        return OpenShootArrangement.dateSpan(from: shoot.capturedFrom, to: shoot.capturedTo)
    }

    private var stillCount: Int {
        switch weight {
        case .resume: 4
        case .lead: 3
        case .larger, .smaller: 2
        }
    }

    private var stillHeight: CGFloat {
        switch weight {
        case .resume: 112
        case .lead: 84
        case .larger: HiFiTokens.Elastic.filmstripFocusedHeight
        case .smaller: HiFiTokens.Elastic.filmstripTileHeight
        }
    }
}

private struct StillStrip: View {
    let paths: [String]
    let height: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: LuminaTokens.Spacing.xs) {
            if paths.isEmpty {
                LuminaTokens.Surface.well
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: HiFiTokens.Layout.recentShootCornerRadius,
                            style: .continuous
                        )
                    )
            } else {
                ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                    StillFrame(path: path, height: height)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
    }
}

/// Press settles the block with a veil. The photographs stay at full strength.
private struct LuminaOpenPlatePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LuminaOpenPlatePressBody(configuration: configuration)
    }

    private struct LuminaOpenPlatePressBody: View {
        let configuration: Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .overlay {
                    LuminaTokens.Ink.primary.opacity(configuration.isPressed ? 0.08 : 0)
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: HiFiTokens.Layout.recentShootCornerRadius,
                        style: .continuous
                    )
                )
                .animation(
                    LuminaTokens.Motion.press(configuration.isPressed, reduceMotion: reduceMotion),
                    value: configuration.isPressed
                )
        }
    }
}

private struct PlateGround: View {
    let path: String

    var body: some View {
        GeometryReader { geo in
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .overlay(LuminaTokens.Surface.porcelain.opacity(0.84))
        .allowsHitTesting(false)
    }
}

private struct StillFrame: View {
    let path: String
    let height: CGFloat

    var body: some View {
        let image = NSImage(contentsOfFile: path)
        let width = height * Self.clampedAspect(of: image)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LuminaTokens.Surface.well
            }
        }
        .frame(width: width, height: height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: HiFiTokens.Layout.recentShootCornerRadius,
                style: .continuous
            )
        )
    }

    /// Keep the photograph's shape. A very wide or very tall frame is eased so one still cannot eat the row.
    private static func clampedAspect(of image: NSImage?) -> CGFloat {
        guard let size = image?.size, size.height > 0 else { return 1 }
        let aspect = size.width / size.height
        return min(max(aspect, 0.72), 1.65)
    }
}
