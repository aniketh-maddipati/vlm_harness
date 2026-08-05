import SwiftUI

/// Stack thumbnail with optional develop preview (full recipe + slow mix crossfade).
struct GradedPhotoView: View {
    let asset: AssetPresentation
    var projectName: String?
    var baseRecipe: DevelopRecipe = .neutral
    var developOffsets: DevelopAdjustments = .zero
    var previewMix: Double = 1
    var contentMode: ContentMode = .fit
    var cornerRadius: CGFloat = LuminaTokens.Radius.photographThumb
    var showDecisionBadge: Bool = false
    var isSelected: Bool = false
    var isLead: Bool = false
    var maxPixelSize: Int = 1200

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gradedImage: NSImage?
    @State private var loadToken = UUID()

    private var appliedRecipe: DevelopRecipe {
        baseRecipe.applying(developOffsets)
    }

    private var useGraded: Bool {
        (appliedRecipe.hasSettings || !developOffsets.isZero) && previewMix > 0.01 && projectName != nil
    }

    var body: some View {
        ZStack {
            StablePhotoView(
                asset: asset,
                contentMode: contentMode,
                cornerRadius: cornerRadius,
                showDecisionBadge: showDecisionBadge && !useGraded,
                isSelected: isSelected,
                matte: LuminaTokens.Surface.well,
                maxPixelSize: maxPixelSize
            )
            .opacity(useGraded ? Double(1 - previewMix) : 1)

            if useGraded, let gradedImage {
                Image(nsImage: gradedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .opacity(previewMix)
                    .transition(reduceMotion ? .identity : .opacity.animation(LuminaTokens.Motion.develop))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    isLead ? LuminaTokens.Line.emphasis : (isSelected ? LuminaTokens.Status.selection.opacity(0.6) : LuminaTokens.Line.hairline),
                    lineWidth: isLead ? 1.5 : LuminaTokens.Line.hairlineWidth
                )
        }
        .task(id: renderKey) {
            await loadGraded()
        }
    }

    private var renderKey: String {
        let r = appliedRecipe
        return "\(asset.id)-\(r.exposure)-\(r.contrast)-\(r.highlights)-\(previewMix)-\(projectName ?? "")"
    }

    private func loadGraded() async {
        guard useGraded, let projectName else {
            gradedImage = nil
            return
        }
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

        let image = await Task.detached(priority: .userInitiated) {
            DevelopEngine.render(url: url, recipe: appliedRecipe, mix: 1)
        }.value

        guard loadToken == token else { return }
        withAnimation(reduceMotion ? nil : LuminaTokens.Motion.develop) {
            gradedImage = image
        }
    }
}
