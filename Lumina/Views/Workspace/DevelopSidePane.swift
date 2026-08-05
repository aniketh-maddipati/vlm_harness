import SwiftUI

/// Trailing develop pane — large graded preview + basic Lightroom-style sliders.
struct DevelopSidePane: View {
    let asset: AssetPresentation
    var projectName: String?
    var baseRecipe: DevelopRecipe
    @Binding var offsets: DevelopAdjustments
    var previewMix: Double = 1

    var body: some View {
        VStack(spacing: 0) {
            header

            DevelopLeadPreview(
                asset: asset,
                projectName: projectName,
                baseRecipe: baseRecipe,
                offsets: offsets,
                previewMix: previewMix
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, LuminaTokens.Spacing.md)
            .padding(.bottom, LuminaTokens.Spacing.sm)

            developControls
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .background(LuminaTokens.Surface.rail)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(width: LuminaTokens.Line.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Develop panel, \(asset.filename)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(asset.filename)
                .font(LuminaTokens.Typeface.navigation(14, weight: .medium))
                .foregroundStyle(LuminaTokens.Ink.primary)
                .lineLimit(1)

            if let captured = asset.capturedAt {
                Text(formattedCaptureDate(captured))
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            } else {
                Text("Capture time unknown")
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LuminaTokens.Spacing.lg)
        .padding(.top, LuminaTokens.Spacing.md)
        .padding(.bottom, LuminaTokens.Spacing.sm)
    }

    private var developControls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LuminaTokens.Spacing.md) {
                developSection("Light") {
                    DevelopSliderRow(title: "Exposure", value: $offsets.exposure, range: -3...3, step: 0.05, unit: " EV")
                    DevelopSliderRow(title: "Contrast", value: $offsets.contrast, range: -100...100, step: 1)
                    DevelopSliderRow(title: "Highlights", value: $offsets.highlights, range: -100...100, step: 1)
                    DevelopSliderRow(title: "Shadows", value: $offsets.shadows, range: -100...100, step: 1)
                    DevelopSliderRow(title: "Whites", value: $offsets.whites, range: -100...100, step: 1)
                    DevelopSliderRow(title: "Blacks", value: $offsets.blacks, range: -100...100, step: 1)
                }

                developSection("Color") {
                    DevelopSliderRow(title: "Temperature", value: $offsets.temperature, range: -800...800, step: 10, unit: " K")
                    DevelopSliderRow(title: "Tint", value: $offsets.tint, range: -100...100, step: 1)
                    DevelopSliderRow(title: "Vibrance", value: $offsets.vibrance, range: -100...100, step: 1)
                    DevelopSliderRow(title: "Saturation", value: $offsets.saturation, range: -100...100, step: 1)
                }

                developSection("Detail") {
                    DevelopSliderRow(title: "Clarity", value: $offsets.clarity, range: -100...100, step: 1)
                    DevelopSliderRow(title: "Texture", value: $offsets.texture, range: -100...100, step: 1)
                    DevelopSliderRow(title: "Dehaze", value: $offsets.dehaze, range: -100...100, step: 1)
                }

                Button("Reset adjustments") {
                    LuminaHaptics.alignment()
                    offsets = .zero
                }
                .font(LuminaTokens.Typeface.meta(13))
                .foregroundStyle(LuminaTokens.Ink.secondary)
                .buttonStyle(LuminaQuietButtonStyle())
                .padding(.top, LuminaTokens.Spacing.xs)
            }
            .padding(.horizontal, LuminaTokens.Spacing.lg)
            .padding(.bottom, LuminaTokens.Spacing.lg)
        }
        .frame(maxHeight: 320)
        .background(LuminaTokens.Surface.porcelain)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LuminaTokens.Line.hairline)
                .frame(height: LuminaTokens.Line.hairlineWidth)
        }
    }

    @ViewBuilder
    private func developSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: LuminaTokens.Spacing.sm) {
            Text(title.uppercased())
                .font(LuminaTokens.Typeface.meta(10, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(LuminaTokens.Ink.tertiary)
            content()
        }
    }

    private func formattedCaptureDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d, yyyy · h:mm:ss a"
        return formatter.string(from: date)
    }
}

// MARK: - Large develop preview

struct DevelopLeadPreview: View {
    let asset: AssetPresentation
    var projectName: String?
    var baseRecipe: DevelopRecipe
    var offsets: DevelopAdjustments
    var previewMix: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gradedImage: NSImage?
    @State private var loadToken = UUID()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LuminaTokens.Surface.well

                if let gradedImage {
                    Image(nsImage: gradedImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                        .opacity(previewMix)
                        .transition(reduceMotion ? .identity : .opacity.animation(LuminaTokens.Motion.develop))
                } else {
                    StablePhotoView(
                        asset: asset,
                        contentMode: .fit,
                        cornerRadius: LuminaTokens.Radius.photographLarge,
                        maxPixelSize: 3200
                    )
                    .opacity(0.35)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographLarge, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LuminaTokens.Radius.photographLarge, style: .continuous)
                    .strokeBorder(LuminaTokens.Line.hairline, lineWidth: LuminaTokens.Line.hairlineWidth)
            }
        }
        .task(id: renderKey) {
            await loadGraded()
        }
    }

    private var renderKey: String {
        let recipe = baseRecipe.applying(offsets)
        return "\(asset.id)-\(recipe.exposure)-\(recipe.contrast)-\(recipe.highlights)-\(recipe.shadows)-\(recipe.temperature)-\(recipe.vibrance)-\(previewMix)-\(projectName ?? "")"
    }

    private func loadGraded() async {
        guard let projectName else { return }
        let token = UUID()
        loadToken = token
        let path = asset.previewPath ?? asset.thumbPath
        guard let path else { return }

        let photo = PhotoRecord(
            id: asset.id,
            rawPath: path,
            filename: asset.filename,
            thumbPath: path,
            proxyPath: path
        )
        guard let url = DevelopEngine.ensureProxy(for: photo, projectName: projectName) else { return }

        let recipe = baseRecipe.applying(offsets)
        let image = await Task.detached(priority: .userInitiated) {
            DevelopEngine.render(url: url, recipe: recipe, mix: 1)
        }.value

        guard loadToken == token else { return }
        withAnimation(reduceMotion ? nil : LuminaTokens.Motion.develop) {
            gradedImage = image
        }
    }
}

struct DevelopSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(LuminaTokens.Typeface.meta(12))
                    .foregroundStyle(LuminaTokens.Ink.secondary)
                Spacer(minLength: 8)
                Text(formattedValue)
                    .font(LuminaTokens.Typeface.count(11))
                    .foregroundStyle(LuminaTokens.Ink.tertiary)
            }
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
        }
    }

    private var formattedValue: String {
        if unit == " EV" {
            return String(format: "%+.2f%@", value, unit)
        }
        if unit == " K" {
            return String(format: "%+.0f%@", value, unit)
        }
        return String(format: "%+.0f", value)
    }
}
