import SwiftUI

/// Sort/filter lens — only shown inside grid overview.
struct DynamicSortBar: View {
    @Binding var sortMode: SortMode
    @Binding var filter: GridFilter

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SortMode.gridLensModes) { mode in
                        lensButton(mode.rawValue, active: sortMode == mode) {
                            withAnimation(LuminaTokens.Motion.photo) {
                                sortMode = mode
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GridFilter.allCases) { f in
                        lensButton(f.rawValue, active: filter == f) {
                            withAnimation(LuminaTokens.Motion.photo) {
                                filter = f
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
    }

    private func lensButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
