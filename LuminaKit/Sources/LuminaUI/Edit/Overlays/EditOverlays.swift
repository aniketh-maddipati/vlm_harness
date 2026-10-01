import SwiftUI
import LuminaCore

// WP-6. What sits above Edit: Variations, Help, the first-run intro, the scene grid, the toast.
// WP-0 stub: the toast only.

public struct EditOverlays: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    public init() {}
    public var body: some View {
        VStack {
            Spacer()
            if let t = model.toast {
                Text(t.text).font(LuminaFont.small(s)).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(LuminaColor.overlayChip)).luminaStatus(AccessibilityID.Edit.toast, t.text)
            }
        }
        .padding(.bottom, 24).allowsHitTesting(false)
    }
}
