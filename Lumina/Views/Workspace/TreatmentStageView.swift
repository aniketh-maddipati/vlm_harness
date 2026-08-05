import SwiftUI

/// Fidelity chip states — driven by PreviewSpine / source availability, never faked.
enum TreatmentFidelity: Equatable {
    case interactivePreview
    case settling
    case fullPreview
    case oneToOneRAW
    case previewsOnly

    var label: String {
        switch self {
        case .interactivePreview: "Interactive preview"
        case .settling: "Settling"
        case .fullPreview: "Full preview"
        case .oneToOneRAW: "1:1 RAW"
        case .previewsOnly: "Previews only — reconnect for full resolution"
        }
    }

    var voiceOverHint: String {
        switch self {
        case .interactivePreview:
            return "Interactive preview. Good for framing decisions; not final colour."
        case .settling:
            return "Settling. Waiting for a sharper proxy."
        case .fullPreview:
            return "Full preview. Suitable for exposure and colour judgement."
        case .oneToOneRAW:
            return "One-to-one RAW pixels. Use for critical sharpness."
        case .previewsOnly:
            return "Source disconnected. Cached previews only — reconnect for full resolution."
        }
    }
}

/// White balance presets — standard Kelvin targets, applied as offsets from
/// the photo's base recipe so Auto/taste edits compose correctly.
enum WhiteBalancePreset: String, CaseIterable, Identifiable {
    case asShot = "As Shot"
    case auto = "Auto"
    case daylight = "Daylight"
    case cloudy = "Cloudy"
    case shade = "Shade"
    case tungsten = "Tungsten"
    case fluorescent = "Fluorescent"
    case flash = "Flash"

    var id: String { rawValue }

    /// Absolute Kelvin / tint target. Nil means reset (As Shot) or computed (Auto).
    var target: (kelvin: Double, tint: Double)? {
        switch self {
        case .asShot, .auto: return nil
        case .daylight: return (5500, 0)
        case .cloudy: return (6500, 3)
        case .shade: return (7500, 8)
        case .tungsten: return (3200, 0)
        case .fluorescent: return (4000, 20)
        case .flash: return (5500, 0)
        }
    }
}

/// Editing surface — opens on ⌘-double-click or T. PDF frames A · 4 / A · 5.
struct TreatmentStageView: View {
    let leader: AssetPresentation
    let references: [AssetPresentation]
    let selectionCount: Int
    /// Photos in the leader's set (family row) — target of Apply to set.
    var setCount: Int = 1
    var projectName: String?
    var baseRecipe: DevelopRecipe
    @Binding var offsets: DevelopAdjustments
    @Binding var previewMode: TreatmentPreviewMode
    var stagedRecipe: DevelopRecipe?
    var fidelity: TreatmentFidelity
    var localOverrideNotes: [AssetID: String] = [:]
    var storyStrip: [AssetPresentation]
    var exifLine: String
    var onClose: () -> Void
    var onOffsetsChange: (DevelopAdjustments) -> Void
    var onStageTreat: () -> Void
    var onConfirmTreat: () -> Void
    var onCancelStage: () -> Void
    var onOpenMore: () -> Void
    var onSelectReference: (AssetID) -> Void
    var onApplyToSet: () -> Void = {}
    var onAddRetouch: (RetouchSpot) -> Void = { _ in }
    var onUndoRetouch: () -> Void = {}
    var onClearRetouch: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingOriginalHold = false
    @State private var oneToOne = false
    @State private var healMode = false
    @State private var healRadius: Double = 0.02
    @State private var scheduler = WorkbenchDevelop.scheduler
    @State private var receipt: String?
    @State private var autoBusy = false

    private var effectiveRecipe: DevelopRecipe {
        if showingOriginalHold || previewMode == .original { return .neutral }
        return baseRecipe
    }

    private var effectiveOffsets: DevelopAdjustments {
        if showingOriginalHold || previewMode == .original { return .zero }
        return offsets
    }

    /// Absolute recipe rendered by the live pipeline.
    private var liveRecipe: DevelopRecipe {
        effectiveRecipe.applying(effectiveOffsets)
    }

    private var hasLiveRAW: Bool {
        guard let rawPath = leader.rawPath else { return false }
        return FileManager.default.fileExists(atPath: rawPath)
    }

    /// Honest fidelity — live scheduler state when the RAW pipeline is active.
    private var effectiveFidelity: TreatmentFidelity {
        guard hasLiveRAW, fidelity != .previewsOnly,
              let live = scheduler.fidelityByPhoto[leader.id] else { return fidelity }
        switch live {
        case .interactive: return .interactivePreview
        case .settling: return .settling
        case .rawSettled, .exportQuality, .beforeOriginal: return .fullPreview
        case .oneToOneRAW: return .oneToOneRAW
        case .proxyFallback: return .interactivePreview
        }
    }

    private var retouchCount: Int {
        baseRecipe.retouch.count
    }

    var body: some View {
        HStack(spacing: 0) {
            storyCollapsedStrip
                .frame(width: 96)

            mainColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controlsColumn
                .frame(width: 324)
                .frame(maxHeight: .infinity)
        }
        .background(LuminaTokens.Surface.table)
        .onExitCommand(perform: onClose)
    }

    // MARK: - Story collapse (96 pt)

    private var storyCollapsedStrip: some View {
        VStack(spacing: 8) {
            Text("Story")
                .font(LuminaTokens.Typeface.meta(10))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(storyStrip.prefix(12)) { asset in
                        StablePhotoView(
                            asset: asset,
                            contentMode: .fit,
                            cornerRadius: 2,
                            maxPixelSize: 240
                        )
                        .frame(width: 48, height: 48 * (1 / max(asset.aspectRatio, 0.1)))
                        .frame(maxHeight: 48)
                        .opacity(0.60)
                    }
                }
            }
            Spacer(minLength: 0)
            Button("Done") { onClose() }
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Done — close treatment")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(LuminaTokens.Surface.tableHead)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
        }
    }

    // MARK: - Main

    private var mainColumn: some View {
        GeometryReader { geo in
            let pad: CGFloat = 28
            // Scale with the window — cap only to protect decode budgets.
            let leaderMaxW = min(max(geo.size.width * 0.90, 700), 1800)
            let showReferences = geo.size.height >= 680 && !references.isEmpty
            VStack(spacing: 12) {
                Spacer(minLength: 4)

                // The photograph at hand — the dominant element in the stage.
                leaderSurface
                    .frame(maxWidth: leaderMaxW)
                    .aspectRatio(leader.aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)

                metadataStrip
                    .frame(maxWidth: leaderMaxW)

                if showReferences {
                    referencesRow
                        .frame(maxWidth: leaderMaxW)
                }

                Spacer(minLength: 4)
            }
            .padding(pad)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// EXIF plus the effective develop values — evolves live as sliders move.
    private var metadataStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(exifLine)
                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let receipt {
                    Text(receipt)
                        .font(LuminaTokens.Typeface.meta(11))
                        .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                        .transition(.opacity)
                }
                fidelityChip
            }
            Text(liveDevelopLine)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(LuminaTokens.Ink.onTable)
                .lineLimit(1)
                .accessibilityLabel("Current develop values: \(liveDevelopLine)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    /// The rendered recipe as a readable line — updates on every adjustment.
    private var liveDevelopLine: String {
        let r = liveRecipe
        var parts: [String] = []
        parts.append(String(format: "WB %.0fK %+.0f", r.temperature, r.tint))
        parts.append(String(format: "EV %+.2f", r.exposure))
        parts.append(String(format: "HL %+.0f", r.highlights))
        parts.append(String(format: "SH %+.0f", r.shadows))
        parts.append(String(format: "C %+.0f", r.contrast))
        if r.vibrance != 0 || r.saturation != 0 {
            parts.append(String(format: "Vib %+.0f · Sat %+.0f", r.vibrance, r.saturation))
        }
        if r.luminanceNR > 0 { parts.append(String(format: "NR %.0f", r.luminanceNR)) }
        if r.sharpness > 0 { parts.append(String(format: "Shp %.0f", r.sharpness)) }
        if retouchCount > 0 { parts.append("\(retouchCount) heal\(retouchCount == 1 ? "" : "s")") }
        return parts.joined(separator: "   ")
    }

    /// Live RAW preview with heal-tap overlay. Falls back to proxy grading
    /// when the original RAW is not on disk.
    private var leaderSurface: some View {
        LiveDevelopView(
            photoID: leader.id,
            asset: leader,
            projectName: projectName,
            recipe: liveRecipe,
            oneToOne: oneToOne
        )
        .overlay {
            if healMode {
                healOverlay
            }
        }
        .accessibilityLabel("Photograph being treated: \(leader.filename)")
    }

    private var healOverlay: some View {
        GeometryReader { geo in
            ZStack {
                // Existing spots.
                ForEach(baseRecipe.retouch) { spot in
                    let d = CGFloat(spot.radius) * geo.size.width * 2
                    Circle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .frame(width: d, height: d)
                        .position(
                            x: CGFloat(spot.x) * geo.size.width,
                            y: CGFloat(spot.y) * geo.size.height
                        )
                }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        addHealSpot(at: location, in: geo.size)
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Heal — click a blemish. Clone-based, applies to export.")
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .padding(8)
        }
    }

    private func addHealSpot(at location: CGPoint, in size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let nx = min(max(Double(location.x / size.width), 0), 1)
        let ny = min(max(Double(location.y / size.height), 0), 1)
        // Donor: horizontally to the side with room, 2.2 radii away.
        let direction: Double = nx < 0.5 ? 1 : -1
        var dx = direction * healRadius * 2.2
        var dy = 0.0
        if nx + dx < 0.02 || nx + dx > 0.98 {
            dx = 0
            dy = (ny < 0.5 ? 1 : -1) * healRadius * 2.2
        }
        let spot = RetouchSpot(x: nx, y: ny, radius: healRadius, sourceDX: dx, sourceDY: dy)
        onAddRetouch(spot)
        LuminaHaptics.decision()
    }

    private var fidelityChip: some View {
        Text(effectiveFidelity.label)
            .font(LuminaTokens.Typeface.meta(11))
            .foregroundStyle(LuminaTokens.Ink.onTable)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .accessibilityLabel(effectiveFidelity.label)
            .accessibilityHint(effectiveFidelity.voiceOverHint)
            .animation(reduceMotion ? nil : LuminaTokens.Motion.fidelityCrossfade, value: effectiveFidelity)
    }

    private var referencesRow: some View {
        HStack(spacing: 14) {
            ForEach(references.prefix(2)) { asset in
                VStack(spacing: 6) {
                    Button { onSelectReference(asset.id) } label: {
                        GradedPhotoView(
                            asset: asset,
                            projectName: projectName,
                            baseRecipe: stagedRecipe ?? (asset.id == leader.id ? baseRecipe : .neutral),
                            developOffsets: stagedRecipe != nil ? .zero : (asset.id == leader.id ? offsets : .zero),
                            previewMix: 1,
                            contentMode: .fit,
                            showDecisionBadge: false,
                            isSelected: false,
                            maxPixelSize: 900
                        )
                        .frame(width: 190, height: 127)
                        .aspectRatio(asset.aspectRatio, contentMode: .fit)
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                    .accessibilityLabel("Compare with \(asset.filename)")

                    if let note = localOverrideNotes[asset.id] {
                        Text(note)
                            .font(LuminaTokens.Typeface.meta(11))
                            .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                            .multilineTextAlignment(.center)
                    } else if stagedRecipe != nil {
                        Text("same recipe, re-evaluated on its own RAW")
                            .font(LuminaTokens.Typeface.meta(11))
                            .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: 190)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls

    private var controlsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if stagedRecipe != nil {
                Text("Staged across \(selectionCount) · ↩ commits, Esc cancels")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }

            // Preview modes and Auto edit each get their own space at the top.
            chipRow
                .padding(.bottom, 8)
            autoEditButton
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    panel("White balance") { whiteBalanceSection }
                    panel("Tone") {
                        slider("Exposure", value: binding(\.exposure), range: -2...2)
                        slider("Highlights", value: binding(\.highlights), range: -100...100)
                        slider("Shadows", value: binding(\.shadows), range: -100...100)
                        slider("Contrast", value: binding(\.contrast), range: -100...100)
                    }
                    panel("Color") {
                        slider("Vibrance", value: binding(\.vibrance), range: -100...100)
                        slider("Saturation", value: binding(\.saturation), range: -100...100)
                    }
                    panel("Detail") { detailSection }
                    panel("Erase / heal") { healSection }
                }
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            Divider()
                .padding(.vertical, 10)

            actionButtons
        }
        .padding(16)
        .background(LuminaTokens.Surface.side)
        .overlay(alignment: .leading) {
            Rectangle().fill(LuminaTokens.Line.hairline).frame(width: 1)
        }
    }

    /// Card container so each control family has its own visual space.
    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(LuminaTokens.Typeface.meta(10, weight: .medium))
                .kerning(0.8)
                .foregroundStyle(LuminaTokens.Ink.tertiary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LuminaTokens.Surface.mist.opacity(0.55))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var autoEditButton: some View {
        Button { applyAutoEdit() } label: {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12))
                Text(autoBusy ? "Analyzing…" : "Auto edit")
                    .font(LuminaTokens.Typeface.navigation(12, weight: .medium))
            }
            .foregroundStyle(LuminaTokens.Ink.primary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LuminaTokens.Surface.mist)
            )
        }
        .buttonStyle(LuminaQuietButtonStyle())
        .disabled(autoBusy)
        .accessibilityLabel("Auto edit")
        .accessibilityHint("Analyzes the photograph and sets white balance and tone automatically. Sliders update to match.")
    }

    private func applyAutoEdit() {
        let path = leader.previewPath ?? leader.thumbPath
        guard let path, !autoBusy else { return }
        autoBusy = true
        Task {
            defer { autoBusy = false }
            guard let s = await AutoDevelop.suggest(imagePath: path) else { return }
            var next = offsets
            // Suggestion values are absolute targets — convert to offsets so
            // taste/base edits compose, and so the sliders land on the result.
            next.exposure = min(max(s.exposure - baseRecipe.exposure, -2), 2)
            next.contrast = min(max(s.contrast - baseRecipe.contrast, -100), 100)
            next.highlights = min(max(s.highlights - baseRecipe.highlights, -100), 100)
            next.shadows = min(max(s.shadows - baseRecipe.shadows, -100), 100)
            next.vibrance = min(max(s.vibrance - baseRecipe.vibrance, -100), 100)
            next.temperature = min(max(s.kelvin - baseRecipe.temperature, -2000), 2000)
            next.tint = min(max(s.tint - baseRecipe.tint, -50), 50)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                commit(next)
            }
            showReceipt("Auto edit applied — sliders updated")
        }
    }

    private func showReceipt(_ text: String) {
        withAnimation { receipt = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation { receipt = nil }
        }
    }

    private var whiteBalanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 5)], spacing: 5) {
                ForEach(WhiteBalancePreset.allCases) { preset in
                    Button {
                        applyWhiteBalancePreset(preset)
                    } label: {
                        Text(preset.rawValue)
                            .font(LuminaTokens.Typeface.meta(11))
                            .foregroundStyle(LuminaTokens.Ink.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(LuminaTokens.Surface.mist)
                            )
                    }
                    .buttonStyle(LuminaQuietButtonStyle())
                    .accessibilityLabel("White balance: \(preset.rawValue)")
                }
            }
            slider("Temperature", value: binding(\.temperature), range: -2000...2000)
            slider("Tint", value: binding(\.tint), range: -50...50)
        }
    }

    private func applyWhiteBalancePreset(_ preset: WhiteBalancePreset) {
        var next = offsets
        switch preset {
        case .asShot:
            next.temperature = 0
            next.tint = 0
            commit(next)
        case .auto:
            let path = leader.previewPath ?? leader.thumbPath
            let base = baseRecipe
            Task {
                guard let path,
                      let estimate = await AutoWhiteBalance.estimate(imagePath: path) else { return }
                var auto = offsets
                auto.temperature = min(max(estimate.kelvin - base.temperature, -2000), 2000)
                auto.tint = min(max(estimate.tint - base.tint, -50), 50)
                commit(auto)
            }
        default:
            guard let target = preset.target else { return }
            next.temperature = min(max(target.kelvin - baseRecipe.temperature, -2000), 2000)
            next.tint = min(max(target.tint - baseRecipe.tint, -50), 50)
            commit(next)
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            slider("Noise reduction", value: binding(\.luminanceNR), range: 0...100)
            slider("Sharpening", value: binding(\.sharpness), range: 0...150)
            Text("RAW-domain when supported · Crop — ⌘⌥C opens the rest")
                .font(LuminaTokens.Typeface.meta(10))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .onTapGesture(perform: onOpenMore)
        }
    }

    private var healSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(retouchCount > 0 ? "\(retouchCount) spot\(retouchCount == 1 ? "" : "s")" : "Clone-based")
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                Spacer()
                Button {
                    healMode.toggle()
                } label: {
                    Text(healMode ? "Healing on" : "Heal")
                        .font(LuminaTokens.Typeface.meta(11, weight: healMode ? .medium : .regular))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(healMode ? LuminaTokens.Status.selection.opacity(0.25) : LuminaTokens.Surface.mist)
                        )
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel(healMode ? "Turn heal mode off" : "Turn heal mode on")
                .accessibilityHint("Click the photograph to remove a blemish with a clone-based heal.")
            }

            if healMode {
                slider("Spot size", value: $healRadius, range: 0.005...0.06)
                HStack(spacing: 8) {
                    if retouchCount > 0 {
                        Button("Undo spot") { onUndoRetouch() }
                            .font(LuminaTokens.Typeface.meta(11))
                            .buttonStyle(LuminaQuietButtonStyle())
                            .accessibilityLabel("Undo last heal spot")
                        Button("Clear \(retouchCount)") { onClearRetouch() }
                            .font(LuminaTokens.Typeface.meta(11))
                            .buttonStyle(LuminaQuietButtonStyle())
                            .accessibilityLabel("Clear all heal spots")
                    }
                }
                Text("Clone-based heal — not generative fill. Renders identically in preview and export.")
                    .font(LuminaTokens.Typeface.meta(10))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            if setCount > 1 {
                Button {
                    onApplyToSet()
                    showReceipt("Applied to \(setCount) in set")
                } label: {
                    Text("Apply to set (\(setCount))  ⌘⇧A")
                        .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(LuminaTokens.Surface.mist)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Apply current treatment to all \(setCount) photographs in this set")
                .accessibilityHint("Each photograph re-evaluates the same recipe on its own file.")
            }

            if selectionCount > 1 {
                Button {
                    if stagedRecipe == nil { onStageTreat() } else { onConfirmTreat() }
                } label: {
                    Text(stagedRecipe == nil ? "Stage across \(selectionCount)  ⌘↩" : "Commit treatment  ↩")
                        .font(LuminaTokens.Typeface.navigation(13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(LuminaTokens.Surface.mist)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel(stagedRecipe == nil
                    ? "Stage treatment across \(selectionCount) gathered photographs"
                    : "Commit staged treatment")
            }

            if stagedRecipe != nil {
                Button("Cancel staging", action: onCancelStage)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .buttonStyle(LuminaQuietButtonStyle())
                    .accessibilityLabel("Cancel staged treatment")
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach([TreatmentPreviewMode.original, .auto, .current], id: \.self) { mode in
                Button {
                    previewMode = mode
                } label: {
                    Text(modeLabel(mode))
                        .font(LuminaTokens.Typeface.meta(12, weight: previewMode == mode ? .medium : .regular))
                        .foregroundStyle(LuminaTokens.Ink.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(previewMode == mode ? LuminaTokens.Surface.well : Color.clear)
                        )
                }
                .buttonStyle(LuminaQuietButtonStyle())
                .accessibilityLabel("Preview \(modeLabel(mode))")
                .accessibilityAddTraits(previewMode == mode ? .isSelected : [])
            }
        }
    }

    private func modeLabel(_ mode: TreatmentPreviewMode) -> String {
        switch mode {
        case .original: "Original"
        case .auto: "Auto"
        case .current: "Current"
        }
    }

    private func commit(_ next: DevelopAdjustments) {
        offsets = next
        previewMode = .current
        onOffsetsChange(next)
    }

    private func binding(_ keyPath: WritableKeyPath<DevelopAdjustments, Double>) -> Binding<Double> {
        Binding(
            get: { offsets[keyPath: keyPath] },
            set: { newValue in
                var next = offsets
                next[keyPath: keyPath] = newValue
                commit(next)
            }
        )
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                Spacer()
                Text(valueLabel(value.wrappedValue, range: range))
                    .font(.system(size: 10, weight: value.wrappedValue == 0 ? .regular : .medium, design: .monospaced))
                    .foregroundStyle(value.wrappedValue == 0 ? LuminaTokens.Ink.tertiary : LuminaTokens.Ink.primary)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { value.wrappedValue = max(0, range.lowerBound) }
            .help("Double-click to reset \(title)")
            Slider(value: value, in: range)
                .controlSize(.small)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
                .accessibilityLabel(title)
                .accessibilityValue(valueLabel(value.wrappedValue, range: range))
                .accessibilityHint("Changes render live. Double-click the label to reset.")
        }
    }

    private func valueLabel(_ v: Double, range: ClosedRange<Double>) -> String {
        if range.upperBound <= 3 { return String(format: "%+.2f", v) }
        if range.upperBound >= 1000 { return String(format: "%+.0fK", v) }
        return String(format: "%+.0f", v)
    }
}
