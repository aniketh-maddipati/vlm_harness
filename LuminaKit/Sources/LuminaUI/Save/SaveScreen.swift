import SwiftUI
import LuminaCore

// WP-7. Save (README §4). WP-0 stub: the summary and the button.

public struct SaveScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}
    public var body: some View {
        let n = model.keptIDs.count
        VStack(alignment: .leading, spacing: 22.scaled(s)) {
            Text("Save").font(LuminaFont.display(LuminaFontSize.display, s))
            Text(n == 0 ? "No keepers yet" : "\(n) keepers ready to save").font(LuminaFont.ui(LuminaFontSize.title3, .semibold, s))
                .accessibilityIdentifier(AccessibilityID.Save.summary)
            HStack {
                ForEach(SaveFormat.allCases, id: \.self) { f in
                    Button(f.rawValue) { model.setFormat(f) }.buttonStyle(.luminaSecondary).accessibilityIdentifier(AccessibilityID.Save.format(f.rawValue))
                        .accessibilityAddTraits(model.save.fmt == f ? .isSelected : [])
                }
            }
            Button(n == 0 ? "Nothing to save yet" : model.save.saved?.sig == model.saveSignature ? "✓ Saved" : model.save.saved != nil ? "Save again · \(n) photos" : "Save \(n) photos") { model.saveNow() }
                .buttonStyle(LuminaPrimaryButtonStyle(height: LuminaHeight.saveButton, radius: LuminaRadius.saveButton, fontSize: LuminaFontSize.button, padding: 22))
                .disabled(n == 0 || model.save.saved?.sig == model.saveSignature)
                .accessibilityIdentifier(AccessibilityID.Save.button)
        }
        .frame(width: model.breakpoints.formColumn(s), alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, model.breakpoints.formTopPadding)
    }
}
