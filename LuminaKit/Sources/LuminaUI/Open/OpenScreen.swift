import SwiftUI
import LuminaCore

// WP-2. Open (README §1). WP-0 stub: the card button only.

public struct OpenScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 28.scaled(s)) {
            Text("Open a shoot").font(LuminaFont.display(LuminaFontSize.display, s))
            Button { model.startCulling() } label: { HStack(spacing: 8) { Text(model.copied == 0 ? "Copy & start culling" : "Continue culling"); KeyHint("⏎") } }
                .buttonStyle(.luminaPrimary).accessibilityIdentifier(AccessibilityID.Open.card)
        }
        .frame(width: model.breakpoints.formColumn(s), alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, model.breakpoints.formTopPadding)
    }
}
