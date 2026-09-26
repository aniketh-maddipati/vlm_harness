import SwiftUI

/// The kept set as one walk. Plates travel; earlier / later / out / Export decide.
struct ElasticStitchView: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        VStack(spacing: 0) {
            bar
            if !session.finalSetAssetIDs.isEmpty
                || session.exportStatusLine != nil
                || session.canResumeExport
                || session.exportSettingsVisible {
                P0ExportControls(session: session)
            }
            sequence
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LuminaTokens.Elastic.paper)
    }

    private var bar: some View {
        let page = session.stitchPage
        let focus = session.focusedAssetID
        let inSet = focus.map(session.isInFinalSet) ?? false
        return HStack(spacing: ElasticLayout.headerGap) {
            ElasticOperationButton(title: "earlier", on: false) {
                if let focus { session.moveInSet(focus, by: -1) }
            }
            .disabled(!inSet || !page.canRetreat)
            .accessibilityIdentifier(P0AccessibilityID.elasticStitchEarlier)

            ElasticOperationButton(title: "later", on: false) {
                if let focus { session.moveInSet(focus, by: 1) }
            }
            .disabled(!inSet || !page.canAdvance)
            .accessibilityIdentifier(P0AccessibilityID.elasticStitchLater)

            ElasticOperationButton(
                title: "out",
                on: focus.map { session.outToggleIsOn([$0]) } ?? false
            ) {
                if let focus { session.classifyOut([focus]) }
            }
            .disabled(focus == nil)
            .accessibilityIdentifier(P0AccessibilityID.pointerCullReject)

            if !page.label.isEmpty {
                Text(page.label)
                    .font(ElasticType.mono(ElasticLayout.headerTextSize))
                    .foregroundStyle(LuminaTokens.Elastic.muted)
                    .fixedSize()
                    .accessibilityLabel("Set \(page.label)")
            }

            Spacer(minLength: 0)
            ElasticExportButton(session: session)
        }
        .padding(.horizontal, ElasticLayout.chromeGutter)
        .frame(height: ElasticLayout.stitchBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuminaTokens.Elastic.shell)
        .overlay(alignment: .bottom) { ElasticHairline() }
    }

    private var sequence: some View {
        let ids = session.finalSetAssetIDs
        return ScrollView {
            ElasticWrapLayout(
                horizontalSpacing: ElasticLayout.stitchGap,
                verticalSpacing: ElasticLayout.stitchGap
            ) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    stitchPlate(id, ordinal: index + 1)
                }
            }
            .padding(.horizontal, ElasticLayout.chromeGutter)
            .padding(.vertical, ElasticLayout.tablePaddingTop)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stitchPlate(_ id: UUID, ordinal: Int) -> some View {
        let asset = session.asset(id)
        let focused = session.focusedAssetID == id
        let width = ElasticLayout.stitchPlate
        let height = width / ElasticLayout.stitchPlateAspect
        let sequence = session.stitchSequenceMark(for: id)
        return VStack(alignment: .leading, spacing: ElasticLayout.shelfGap) {
            ElasticPlateButton {
                session.setFocus(id)
            } label: {
                ZStack {
                    LuminaTokens.Elastic.deep
                    if let path = asset?.gridThumbPath ?? asset?.thumbPath {
                        ChapterPlateImage(path: path)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.stitchPlateRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let sequence {
                        ElasticSequenceChip(mark: sequence)
                            .padding(ElasticLayout.markInset)
                    }
                }
                .contentShape(Rectangle())
            }
            .elasticMarked(
                radius: ElasticLayout.stitchPlateRadius,
                ringed: focused,
                inSet: true,
                sequence: sequence
            )
            Text("\(ordinal)")
                .font(ElasticType.mono(ElasticLayout.stitchOrdinalSize))
                .foregroundStyle(LuminaTokens.Elastic.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(P0AccessibilityID.elasticTile(id))
        .accessibilityLabel("photograph")
        .accessibilityValue("\(ordinal)")
    }
}
