import SwiftUI
import LuminaCore

// WP-3. Cull (README §2, LAYOUT_SIZING §5): the justified grid, the preview column from 900
// wide, and the footer. Keys arrive through `KeyRouter`; nothing here reads the keyboard.

public struct CullScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let bp = Breakpoints(CGSize(width: geo.size.width, height: model.windowSize.height))
            VStack(spacing: 0) {
                if model.visiblePhotos.isEmpty {
                    empty
                } else {
                    HStack(spacing: 0) {
                        CullGridView()
                        if bp.cullHasPreview, let current = model.shoot.photo(model.cullCur) {
                            CullPreview(photo: current).frame(width: bp.cullPreviewWidth.rounded())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                CullFooter()
            }
        }
    }

    /// Nothing copied or imported yet.
    private var empty: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12.scaled(s)) {
                Text(CullCopy.empty).font(LuminaFont.body(s)).foregroundStyle(LuminaColor.textSecondary)
                Button(CullCopy.openShoot) { model.go(.open) }.buttonStyle(.luminaSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, (16 + 48).scaled(s)).padding(.horizontal, 20.scaled(s)).padding(.bottom, 24.scaled(s))
        }
        .accessibilityIdentifier(AccessibilityID.Cull.grid)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
