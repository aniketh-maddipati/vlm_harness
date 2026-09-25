import SwiftUI

/// Top band: the only exposure set. Always visible — empty still names the handful.
struct ElasticSetShelf: View {
    @Bindable var session: P0SessionModel
    /// A drag is over the shelf — the dashed ring says it will land.
    @State private var dropTargeted = false
    /// Tiles that just landed, scaled up until the settle animation completes.
    @State private var landingIDs: Set<UUID> = []

    var body: some View {
        let ids = session.finalSetAssetIDs
        HStack(spacing: ElasticLayout.shelfGap) {
            Button {
                session.revealSet()
            } label: {
                VStack(alignment: .leading, spacing: ElasticType.lineSpacing(
                    size: ElasticLayout.shelfLabelSize, lineHeight: ElasticLayout.shelfLabelLineHeight
                )) {
                    Text(CopyContract.setShelfLabel)
                    Text("\(ids.count)")
                }
                .font(ElasticType.mono(ElasticLayout.shelfLabelSize))
                .foregroundStyle(LuminaTokens.Elastic.muted)
                .frame(width: ElasticLayout.shelfLabelWidth, alignment: .leading)
            }
            .buttonStyle(LuminaElasticButtonStyle())
            .disabled(ids.isEmpty)
            .accessibilityLabel(CopyContract.setShelfLabel)

            if ids.isEmpty {
                Text(CopyContract.setShelfExposureLine)
                    .font(ElasticType.sans(ElasticLayout.shelfExposureLineSize))
                    .foregroundStyle(LuminaTokens.Elastic.muted.opacity(ElasticLayout.shelfExposureLineOpacity))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ElasticLayout.shelfGap) {
                        ForEach(ids, id: \.self) { id in
                            shelfTile(id)
                        }
                    }
                    .padding(.vertical, ElasticLayout.keyPillPaddingV)
                    .padding(.horizontal, ElasticLayout.ringOuter)
                }
                .frame(maxWidth: .infinity)
            }

            exportButton
        }
        .padding(.horizontal, ElasticLayout.chromeGutter)
        .frame(height: ElasticLayout.setShelfHeightV2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // `#EFECE6` while the set strip is held; `#F6F4F0` otherwise.
        .background(
            dropTargeted || session.peek == .set
                ? LuminaTokens.Elastic.shellAlt
                : LuminaTokens.Elastic.shell
        )
        .animation(LuminaTokens.Motion.selection, value: dropTargeted)
        .overlay(alignment: .bottom) { ElasticHairline() }
        .overlay {
            if dropTargeted {
                Rectangle()
                    .inset(by: ElasticLayout.shelfDropRingInset)
                    .strokeBorder(
                        LuminaTokens.Elastic.ink,
                        style: StrokeStyle(
                            lineWidth: ElasticLayout.shelfDropRingWidth,
                            dash: ElasticLayout.shelfDropRingDash
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        // Frames dragged from the table or strip land here and join the set.
        .dropDestination(for: String.self) { payloads, _ in
            let ids = payloads.flatMap(ElasticDragPayload.decode)
            guard !ids.isEmpty else { return false }
            let added = session.dropOnShelf(ids)
            guard added > 0 else { return true }
            withAnimation(LuminaTokens.Motion.develop) {
                landingIDs.formUnion(ids)
            } completion: {
                withAnimation(LuminaTokens.Motion.develop) {
                    landingIDs.subtract(ids)
                }
            }
            return true
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
    }

    private func shelfTile(_ id: UUID) -> some View {
        let asset = session.asset(id)
        let edited = recipeDiffersFromShot(asset)
        let note = asset?.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: ElasticLayout.shelfNoteGap) {
            ZStack(alignment: .bottomLeading) {
                LuminaTokens.Elastic.shelfThumbFill
                if let path = asset?.gridThumbPath ?? asset?.thumbPath {
                    ChapterPlateImage(path: path)
                }
                if edited {
                    Text(CopyContract.setShelfEditedFact)
                        .font(ElasticType.mono(ElasticLayout.shelfEditedFactSize, weight: .medium))
                        .foregroundStyle(LuminaTokens.Elastic.shellAlt)
                        .padding(.horizontal, ElasticLayout.shelfEditedFactPaddingH)
                        .padding(.vertical, ElasticLayout.shelfEditedFactPaddingV)
                        .background(
                            LuminaTokens.Elastic.ink.opacity(ElasticLayout.shelfEditedFactOpacity),
                            in: RoundedRectangle(
                                cornerRadius: ElasticLayout.shelfEditedFactRadius,
                                style: .continuous
                            )
                        )
                        .padding(ElasticLayout.shelfEditedFactInset)
                }
            }
            .frame(width: ElasticLayout.shelfTileV2.width, height: ElasticLayout.shelfTileV2.height)
            .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.shelfTileRadius, style: .continuous))
            .elasticMarked(radius: ElasticLayout.shelfTileRadius, ringed: session.focusedAssetID == id, inSet: false)
            .scaleEffect(landingIDs.contains(id) ? ElasticLayout.shelfLandScale : 1)
            .animation(LuminaTokens.Motion.develop, value: landingIDs.contains(id))
            .elasticBorn(ElasticLayout.bornTableMs)
            .contentShape(Rectangle())
            .onTapGesture {
                session.setFocus(id)
                session.openFocusedPhotograph()
            }

            if let note, !note.isEmpty {
                Text(note)
                    .font(ElasticType.mono(ElasticLayout.shelfNoteSize))
                    .foregroundStyle(LuminaTokens.Elastic.muted.opacity(ElasticLayout.shelfNoteOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: ElasticLayout.shelfTileV2.width, alignment: .leading)
            }
        }
    }

    /// Quiet fact only: recipe differs from shot. Shelf tiles are already in-set —
    /// edited frames outside the set never appear here.
    private func recipeDiffersFromShot(_ asset: AssetRecord?) -> Bool {
        asset?.recipe?.hasSettings == true
    }

    private var exportButton: some View {
        Button {
            session.chooseAndExportKept()
        } label: {
            HStack(spacing: ElasticLayout.exportGap) {
                Text(session.elasticExportLabel)
                    .font(ElasticType.sans(ElasticLayout.exportTextSize, weight: .medium))
                Text("⌘E")
                    .font(ElasticType.mono(ElasticLayout.keyPillSize, weight: .semibold))
                    .padding(.horizontal, ElasticLayout.keyPillPaddingH)
                    .padding(.vertical, ElasticLayout.keyPillPaddingV)
                    .background(
                        LuminaTokens.Elastic.shell.opacity(ElasticLayout.keyPillOpacity),
                        in: RoundedRectangle(cornerRadius: ElasticLayout.keyPillRadius, style: .continuous)
                    )
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(LuminaTokens.Elastic.shell)
            .padding(.horizontal, ElasticLayout.exportPadding)
            .frame(height: ElasticLayout.exportHeight)
            .background(
                LuminaTokens.Elastic.ink,
                in: RoundedRectangle(cornerRadius: ElasticLayout.exportRadius, style: .continuous)
            )
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .disabled(session.isExporting)
    }
}
