import SwiftUI

/// Grid overview lens — sort/filter bar + collection grid, not a session spine mode.
struct GridOverviewView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.closeGridOverview()
                } label: {
                    Label("Back to canvas", systemImage: "chevron.left")
                }
                .buttonStyle(LuminaPressStyle())
                Spacer()
                Text("Grid overview")
                    .font(.headline)
                Spacer()
                Text("\(model.displayedPhotos.count) shown")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            DynamicSortBar(sortMode: $model.sortMode, filter: $model.filter)

            SessionPhotoGrid(
                photos: model.displayedPhotos,
                selected: Set(model.cursor.map { [$0] } ?? []),
                onToggle: {
                    model.setCursor($0)
                    model.lens = nil
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
