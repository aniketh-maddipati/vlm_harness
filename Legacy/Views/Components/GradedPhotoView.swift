// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
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
    var tableBirth: Bool = false

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
                maxPixelSize: maxPixelSize,
                tableBirth: tableBirth
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
        // Full recipe fingerprint — a partial key silently drops slider changes
        // (temperature/tint/shadows used to never re-render).
        let edit = EditRecipe(from: appliedRecipe, id: UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID())
        return "\(asset.id)|\(edit.valueFingerprint)|\(previewMix)|\(projectName ?? "")|\(maxPixelSize)"
    }

    private func loadGraded() async {
        guard useGraded, let projectName else {
            gradedImage = nil
            return
        }
        // Coalesce slider bursts — `.task(id:)` cancels this on the next change.
        try? await Task.sleep(nanoseconds: 30_000_000)
        if Task.isCancelled { return }

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

        guard loadToken == token, !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : LuminaTokens.Motion.develop) {
            gradedImage = image
        }
    }
}
