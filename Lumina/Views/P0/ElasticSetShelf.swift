import SwiftUI

struct ElasticSetShelf: View {
    @Bindable var session: P0SessionModel
    /// A drag is over the shelf — the dashed ring says it will land.
    @State private var dropTargeted = false

    var body: some View {
        let ids = session.finalSetAssetIDs
        HStack(spacing: ElasticLayout.shelfGap) {
            VStack(alignment: .leading, spacing: ElasticType.lineSpacing(
                size: ElasticLayout.shelfLabelSize, lineHeight: ElasticLayout.shelfLabelLineHeight
            )) {
                Text("set")
                Text("\(ids.count)")
            }
            .font(ElasticType.mono(ElasticLayout.shelfLabelSize))
            .foregroundStyle(LuminaTokens.Elastic.muted)
            .frame(width: ElasticLayout.shelfLabelWidth, alignment: .leading)

            if !session.assets.isEmpty {
                ElasticSetButton(on: session.setToggleIsOn(session.assets.map(\.id))) {
                    session.classifySet(session.assets.map(\.id))
                }
            }

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

            exportButton
        }
        .padding(.horizontal, ElasticLayout.chromeGutter)
        .frame(height: ElasticLayout.setShelfHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // `#EFECE6` while the set strip is held; `#F6F4F0` otherwise.
        .background(session.peek == .set ? LuminaTokens.Elastic.shellAlt : LuminaTokens.Elastic.shell)
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
        // Frames dragged from the table land here and join the set.
        .dropDestination(for: String.self) { payloads, _ in
            let ids = payloads.flatMap(ElasticDragPayload.decode)
            guard !ids.isEmpty else { return false }
            session.dropOnShelf(ids)
            return true
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
    }

    private func shelfTile(_ id: UUID) -> some View {
        let asset = session.asset(id)
        return ZStack {
            LuminaTokens.Elastic.shelfThumbFill
            if let path = asset?.gridThumbPath ?? asset?.thumbPath {
                ChapterPlateImage(path: path)
            }
        }
        .frame(width: ElasticLayout.shelfTile.width, height: ElasticLayout.shelfTile.height)
        .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.shelfTileRadius, style: .continuous))
        .elasticMarked(radius: ElasticLayout.shelfTileRadius, ringed: session.focusedAssetID == id, inSet: false)
        .contentShape(Rectangle())
        .onTapGesture {
            session.setFocus(id)
            session.openFocusedPhotograph()
        }
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

/// `display:flex; flex-wrap:wrap; gap: v h` — groups flow left to right and wrap.
