import SwiftUI
import LuminaCore

// WP-5. The controls column (README §3): header, tools, sections, sliders, bottom bar.
// WP-0 stub: the Light values as text.

public struct EditControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(EditSetting.of(model.edit.section), id: \.key) { st in
                HStack { Text(st.label); Spacer(); Text(String(format: "%g", model.value(st.key))).foregroundStyle(LuminaColor.textTertiary) }
                    .font(LuminaFont.body(s)).frame(minHeight: LuminaHeight.sliderRowMin.scaled(s))
            }
            Spacer()
        }
        .padding(16).background(LuminaColor.bgApp)
    }
}
