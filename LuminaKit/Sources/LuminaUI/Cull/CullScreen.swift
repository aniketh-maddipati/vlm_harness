import SwiftUI
import LuminaCore

// WP-3. Cull (README §2). WP-0 stub: an unjustified grid and the footer's two buttons.

public struct CullScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 6) {
                    ForEach(model.visiblePhotos) { p in
                        PhotoThumb(p, maxPoint: 150).frame(height: 100).clipShape(RoundedRectangle(cornerRadius: LuminaRadius.tile))
                            .overlay(RoundedRectangle(cornerRadius: LuminaRadius.tile).stroke(LuminaColor.textPrimary, lineWidth: model.cullCur == p.id ? 2 : 0))
                            .opacity(model.decisions.keep[p.id] == false ? 0.4 : 1)
                            .onTapGesture { model.select(p.id) }
                            .accessibilityElement().accessibilityIdentifier(AccessibilityID.Cull.tile(p.id))
                            .accessibilityValue(model.decisions.keep[p.id] == true ? "kept" : model.decisions.keep[p.id] == false ? "out" : "undecided")
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier(AccessibilityID.Cull.grid)
            HStack {
                Text("\(model.decisions.keptCount + model.decisions.outCount)/\(model.total) decided").font(LuminaFont.small(s))
                Spacer()
                Button("Save \(model.decisions.keptCount) keepers →") { model.go(.save) }.buttonStyle(LuminaPrimaryButtonStyle(height: LuminaHeight.footerButton))
                    .accessibilityIdentifier(AccessibilityID.Cull.toSave)
            }
            .padding(.horizontal, 20).frame(minHeight: 56.scaled(s)).background(LuminaColor.bgPanel)
        }
    }
}
