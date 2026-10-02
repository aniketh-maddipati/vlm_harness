import SwiftUI
import LuminaCore

// WP-2. Open (README §1): get photos in. One centred column: the title, the card, the import
// row, the folder to reopen, Recent. The wording and every number shown come from
// `AppModel+OpenText`; what the buttons do is in `AppModel+Open`.

public struct OpenScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let bp = model.breakpoints
            // clamp(560, 0.46 × width, 760) × S, and never wider than the space there is.
            let column = max(0, min(bp.formColumn(s), geo.size.width - 2 * 16.scaled(s)))
            ScrollView(.vertical) {
                FormColumn(column: column, top: bp.formTopPadding, bottom: 24.scaled(s), maxTop: 72, viewport: geo.size.height) {
                    OpenColumn()
                }
                .frame(width: geo.size.width)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .luminaFileDrop()
        .onAppear {
            OpenPickers.install(model)
            OpenDebug.apply(model)
        }
    }
}

struct OpenColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    var body: some View {
        VStack(alignment: .leading, spacing: 28.scaled(s)) {
            VStack(alignment: .leading, spacing: 6.scaled(s)) {
                Text("Open a shoot").font(LuminaFont.display(LuminaFontSize.display, s))
                    .accessibilityAddTraits(.isHeader)
                Text("Lumina reads the card and never writes to it. Copies go to ~/Pictures/Lumina and are checked before you see them.")
                    .font(LuminaFont.body(s)).foregroundStyle(LuminaColor.textSecondary)
                    .openLineHeight(LuminaFontSize.body, s)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Without a card there is nothing to copy: the tile only shows for a shoot.
            if !model.shoot.isEmpty { OpenCardTile() }
            OpenImportBlock()
            if model.openShowsReopen { OpenReopenRow() }
            if model.openShowsRecent { OpenRecent() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
