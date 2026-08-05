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

/// Editing surface — opens on ⌘-double-click or T. PDF frames A · 4 / A · 5.
struct TreatmentStageView: View {
    let leader: AssetPresentation
    let references: [AssetPresentation]
    let selectionCount: Int
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingOriginalHold = false
    @State private var oneToOne = false

    private var effectiveRecipe: DevelopRecipe {
        if showingOriginalHold || previewMode == .original { return .neutral }
        return baseRecipe
    }

    private var effectiveOffsets: DevelopAdjustments {
        if showingOriginalHold || previewMode == .original { return .zero }
        return offsets
    }

    var body: some View {
        HStack(spacing: 0) {
            storyCollapsedStrip
                .frame(width: 96)

            mainColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controlsColumn
                .frame(width: 300)
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
            let pad: CGFloat = 30
            let leaderMaxW = min(880, geo.size.width - pad * 2)
            VStack(spacing: 14) {
                Spacer(minLength: 8)

                GradedPhotoView(
                    asset: leader,
                    projectName: projectName,
                    baseRecipe: effectiveRecipe,
                    developOffsets: effectiveOffsets,
                    previewMix: 1,
                    contentMode: .fit,
                    showDecisionBadge: false,
                    isSelected: false,
                    maxPixelSize: oneToOne ? 4096 : 2200
                )
                .frame(maxWidth: leaderMaxW)
                .aspectRatio(leader.aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)

                HStack(alignment: .firstTextBaseline) {
                    Text(exifLine)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    fidelityChip
                }
                .frame(maxWidth: leaderMaxW)

                referencesRow
                    .frame(maxWidth: leaderMaxW)

                Spacer(minLength: 8)
            }
            .padding(pad)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var fidelityChip: some View {
        Text(fidelity.label)
            .font(LuminaTokens.Typeface.meta(11))
            .foregroundStyle(LuminaTokens.Ink.onTable)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .accessibilityLabel(fidelity.label)
            .accessibilityHint(fidelity.voiceOverHint)
            .animation(reduceMotion ? nil : LuminaTokens.Motion.fidelityCrossfade, value: fidelity)
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
                        .frame(width: 250, height: 167)
                        .aspectRatio(asset.aspectRatio, contentMode: .fit)
                    }
                    .buttonStyle(LuminaQuietButtonStyle())

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
                .frame(width: 250)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls

    private var controlsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if stagedRecipe != nil {
                Text("Staged across \(selectionCount) · ↩ commits, Esc cancels")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            chipRow

            slider("Exposure", value: binding(\.exposure), range: -2...2)
            slider("Temperature", value: binding(\.temperature), range: -50...50)
            slider("Tint", value: binding(\.tint), range: -50...50)
            slider("Highlights", value: binding(\.highlights), range: -100...100)
            slider("Shadows", value: binding(\.shadows), range: -100...100)
            slider("Blacks", value: binding(\.blacks), range: -100...100)
            slider("Contrast", value: binding(\.contrast), range: -100...100)

            Text("Crop · Noise · Sharpen — ⌘⌥C opens the rest")
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.tertiary)
                .onTapGesture(perform: onOpenMore)

            Spacer(minLength: 0)

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
            }

            if stagedRecipe != nil {
                Button("Cancel staging", action: onCancelStage)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                    .buttonStyle(LuminaQuietButtonStyle())
            }
        }
        .padding(16)
        .background(LuminaTokens.Surface.side)
        .overlay(alignment: .leading) {
            Rectangle().fill(LuminaTokens.Line.hairline).frame(width: 1)
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

    private func binding(_ keyPath: WritableKeyPath<DevelopAdjustments, Double>) -> Binding<Double> {
        Binding(
            get: { offsets[keyPath: keyPath] },
            set: { newValue in
                var next = offsets
                next[keyPath: keyPath] = newValue
                offsets = next
                previewMode = .current
                onOffsetsChange(next)
            }
        )
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(LuminaTokens.Typeface.meta(11))
                .foregroundStyle(LuminaTokens.Ink.secondary)
            Slider(value: value, in: range)
                .controlSize(.small)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }
}
