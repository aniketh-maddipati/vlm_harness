import SwiftUI
import LuminaCore

// WP-7. Save (README §4, LAYOUT_SIZING §5 "Open and Save"). Every word comes from
// `model.savePresentation`; every action goes to the model. The view only lays out.

public struct SaveScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// Natural heights of the column's parts: everything above the Save button, the button row,
    /// and the saved card.
    @State private var upperHeight: CGFloat = 0
    @State private var rowHeight: CGFloat = 0
    @State private var cardHeight: CGFloat = 0

    public init() {}

    public var body: some View {
        let p = model.savePresentation, bp = model.breakpoints, gap = 22.scaled(s)
        GeometryReader { geo in
            // Content that fits sits ⅓ : ⅔ in the space under the top bar, never more than the
            // form's top padding from it and never with less room below than above (R-57).
            // When it doesn't fit, the column starts 24 from the top, the part above the button
            // scrolls, and the button stays where it can be reached (R-50). The saved card stays
            // under the button while that leaves the options room; otherwise it scrolls with them.
            let minTop: CGFloat = 24, card = p.savedTitle == nil ? 0 : gap + cardHeight
            let free = geo.size.height - (upperHeight + gap + rowHeight + card)
            let fits = upperHeight == 0 || free >= 2 * minTop
            let top = fits ? clamp(minTop, free / 3, max(minTop, bp.formTopPadding)) : minTop
            let room = geo.size.height - top - gap - rowHeight - 12.scaled(s)
            let pinCard = fits || room - card >= 160.scaled(s)
            VStack(alignment: .leading, spacing: gap) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: gap) {
                        upper(p, gap: gap)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { upperHeight = $0 }
                        if !pinCard { savedCard(p) }
                    }
                }
                .scrollDisabled(fits)
                .scrollIndicators(fits ? .hidden : .automatic)
                .frame(height: upperHeight == 0 ? nil : fits ? upperHeight : max(60.scaled(s), room - (pinCard ? card : 0)))
                saveRow(p)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
                if pinCard { savedCard(p) }
            }
            .animation(LuminaMotion.savedCard(reduce), value: model.save.saved != nil)
            .frame(width: bp.formColumn(s), alignment: .leading)
            .padding(.top, top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .clipped()
        .onAppear { SavePanels.install(on: model) }
    }

    // MARK: above the button

    private func upper(_ p: SavePresentation, gap: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            // The title and the summary are one block for assistive tech and the layout tests:
            // `save.summary` is where the Save column starts, and it is as wide as the column.
            VStack(alignment: .leading, spacing: gap) {
                VStack(alignment: .leading, spacing: 6.scaled(s)) {
                    Text(SavePresentation.title).font(LuminaFont.display(LuminaFontSize.display, s))
                        .accessibilityAddTraits(.isHeader)
                    Text(SavePresentation.subtitle).font(LuminaFont.body(s)).foregroundStyle(LuminaColor.textSecondary)
                        .saveLineHeight(LuminaFontSize.body, s)
                }
                VStack(alignment: .leading, spacing: 4.scaled(s)) {
                    Text(p.summary).font(LuminaFont.ui(LuminaFontSize.title3, .semibold, s))
                    if !p.behind.isEmpty {
                        let behind = Text(p.behind).font(LuminaFont.caption(s)).foregroundStyle(LuminaColor.textTertiary)
                        let finish = Button { model.go(.cull) } label: { Text("Finish culling").underline().foregroundStyle(LuminaColor.textPrimary) }
                            .buttonStyle(LuminaLinkButtonStyle(size: LuminaFontSize.caption)).saveInlineLink(s)
                            .accessibilityLabel("Finish culling")
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 8.scaled(s)) { behind.lineLimit(1); if p.hasUndecided { finish } }
                            VStack(alignment: .leading, spacing: 4.scaled(s)) { behind.fixedSize(horizontal: false, vertical: true); if p.hasUndecided { finish } }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.Save.summary)
            .accessibilityLabel(p.summary).accessibilityValue(p.behind)

            VStack(alignment: .leading, spacing: 10.scaled(s)) {
                Text(SavePresentation.saveFor).font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textTertiary)
                SaveFormatControl()
                Text(p.description).font(LuminaFont.caption(s)).foregroundStyle(LuminaColor.textSecondary)
                    .saveLineHeight(LuminaFontSize.caption, s)
                HStack(alignment: .firstTextBaseline, spacing: 10.scaled(s)) {
                    Text(p.destination).font(LuminaFont.mono(LuminaFontSize.small, s)).foregroundStyle(LuminaColor.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                        .accessibilityLabel("Saves to \(p.destination)")
                    Button("Change…") { model.chooseDestination() }
                        .buttonStyle(LuminaLinkButtonStyle(size: LuminaFontSize.small)).saveInlineLink(s)
                        .fixedSize().layoutPriority(1)
                        .disabled(!p.canChangeDestination).opacity(p.canChangeDestination ? 1 : 0.5)
                        .help(p.canChangeDestination ? "Choose another folder" : "The .xmp files always go next to each photo")
                        .accessibilityLabel("Change where it saves")
                }
            }

            if p.showsIncludeEdits { SaveIncludeEditsRow(subline: p.editsSubline) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: the button and what it did

    private func saveRow(_ p: SavePresentation) -> some View {
        let button = Button { model.saveNow() } label: {
            HStack(spacing: 10.scaled(s)) {
                Text(p.buttonLabel).lineLimit(1)
                if model.breakpoints.showsKeyHints { KeyHint("⏎") }
            }
        }
        .buttonStyle(LuminaPrimaryButtonStyle(height: LuminaHeight.saveButton, radius: LuminaRadius.saveButton, fontSize: LuminaFontSize.button, padding: 22))
        .disabled(!p.buttonEnabled)
        .accessibilityIdentifier(AccessibilityID.Save.button).accessibilityLabel(p.buttonLabel)
        let note = Text(p.note).font(LuminaFont.caption(s, id: AccessibilityID.Save.note))
            .foregroundStyle(p.noteIsError ? LuminaColor.errorText : model.save.message != nil ? LuminaColor.textSecondary : LuminaColor.textTertiary)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14.scaled(s)) { button; if !p.note.isEmpty { note.lineLimit(1).luminaStatus(AccessibilityID.Save.note, p.note) } }
            VStack(alignment: .leading, spacing: 8.scaled(s)) { button; if !p.note.isEmpty { note.fixedSize(horizontal: false, vertical: true).luminaStatus(AccessibilityID.Save.note, p.note) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func savedCard(_ p: SavePresentation) -> some View {
        if let title = p.savedTitle {
            SaveSavedCard(title: title, hint: p.savedHint ?? "")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                .transition(.offset(y: LuminaMotion.savedCardRise.scaled(s)).combined(with: .opacity))
        }
    }
}
