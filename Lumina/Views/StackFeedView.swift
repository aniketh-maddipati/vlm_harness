import SwiftUI

/// Collapsed stack cards — one card per cluster/moment in the working feed.
struct StackFeedView: View {
    @Bindable var model: ProjectViewModel
    let clusters: [PhotoCluster]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)], spacing: 16) {
                ForEach(Array(clusters.enumerated()), id: \.element.id) { index, cluster in
                    StackCard(cluster: cluster, members: members(of: cluster), model: model) {
                        model.openStack(at: index)
                    }
                }
            }
            .padding(20)
        }
    }

    private func members(of cluster: PhotoCluster) -> [PhotoRecord] {
        guard let photos = model.project?.photos else { return [] }
        let map = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        return cluster.photoIDs.compactMap { map[$0] }
    }
}

struct StackCard: View {
    let cluster: PhotoCluster
    let members: [PhotoRecord]
    @Bindable var model: ProjectViewModel
    let onOpen: () -> Void

    private var hero: PhotoRecord? {
        members.first(where: { $0.id == cluster.heroID }) ?? members.max(by: { $0.cullScore < $1.cullScore })
    }

    private var uncertainCount: Int {
        members.filter(\.isUncertain).count
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    stackFan
                    Text("\(members.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(cluster.label)
                    .font(.headline)
                    .lineLimit(1)
                Text(cluster.whyGrouped)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if uncertainCount > 0 {
                    Text("\(uncertainCount) need you")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                } else if members.allSatisfy({ $0.tier != .unranked && !$0.isUncertain }) {
                    Text("Clear")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(LuminaPressStyle(pressedScale: 0.97))
    }

    @ViewBuilder
    private var stackFan: some View {
        ZStack {
            ForEach(Array(members.prefix(4).enumerated()), id: \.element.id) { i, photo in
                PhotoImageView(photo: photo, tier: .preview, contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .rotationEffect(.degrees(Double(i) * 2.5 - 3.5))
                    .offset(x: CGFloat(i) * 6, y: CGFloat(i) * 3)
                    .opacity(i == 0 ? 1 : 0.85 - Double(i) * 0.12)
                    .zIndex(Double(4 - i))
            }
        }
        .padding(.horizontal, 8)
    }
}
