import SwiftUI

/// Full-width swim lane — faint fill, inset header rule, optional scene break above.
struct SwimLaneContainer<Content: View>: View {
    let laneHeader: String?
    let sceneBreakBefore: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let sceneBreakBefore {
                Text(sceneBreakBefore)
                    .font(LuminaTokens.Typeface.meta(11))
                    .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
            }

            VStack(alignment: .leading, spacing: 0) {
                if let laneHeader {
                    HStack(spacing: 0) {
                        Text(laneHeader)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(LuminaTokens.Ink.onTableSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(HiFiTokens.SwimLane.headerInset)
                            .frame(height: 1.5)
                    }
                }

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HiFiTokens.SwimLane.fill)
        }
    }
}
