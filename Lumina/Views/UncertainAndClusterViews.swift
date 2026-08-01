import SwiftUI
import AppKit

struct UncertainQueueView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Uncertain")
                    .font(.headline)
                Text("· \(model.uncertainCount) of \(model.totalCount)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.decisionBudgetText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding()

            if let photo = model.selectedPhoto, let project = model.project {
                let peers = related(to: photo)
                VStack(spacing: 12) {
                    Text(photo.whySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    if peers.count >= 2 {
                        ComparePairView(
                            left: peers[0],
                            right: peers[1],
                            projectName: project.name,
                            mix: $model.compareMix,
                            selectedID: model.selectedPhotoID,
                            onSelect: { model.selectPhoto($0) }
                        )
                        .frame(maxHeight: 420)
                        .padding(.horizontal)
                    } else {
                        SoftPreviewView(
                            photo: photo,
                            projectName: project.name,
                            baseline: project.profile,
                            offsets: model.globalAdjustments.merged(with: photo.perPhotoAdjustments ?? .zero),
                            mix: model.showBefore ? 0 : model.softRender.mix,
                            showBefore: model.showBefore
                        )
                        .frame(maxHeight: 420)
                        .padding(.horizontal)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(peers) { related in
                                Button {
                                    model.selectPhoto(related.id)
                                } label: {
                                    VStack {
                                        RelatedThumb(path: related.displayThumbPath, selected: related.id == photo.id)
                                        Text(String(format: "%.2f", related.cullScore))
                                            .font(.caption2.monospacedDigit())
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    HStack(spacing: 16) {
                        Button("Reject (X)") { model.markReject() }
                        Button("Hero") { model.markHero() }
                        Button("Keep (P)") { model.markKeep() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No uncertain photos",
                    systemImage: "checkmark.seal",
                    description: Text("High-confidence culls and edits are done. Switch sort mode to explore.")
                )
            }
        }
    }

    private func related(to photo: PhotoRecord) -> [PhotoRecord] {
        guard let photos = model.project?.photos else { return [photo] }
        if let burst = photo.burstID {
            let group = photos.filter { $0.burstID == burst }.sorted { $0.cullScore > $1.cullScore }
            if group.count > 1 { return group }
        }
        if let cluster = photo.clusterID {
            return photos.filter { $0.clusterID == cluster }.sorted { $0.cullScore > $1.cullScore }
        }
        return [photo]
    }
}

struct ClusterCullView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        let clusters = model.clusters
        VStack(spacing: 0) {
            if clusters.isEmpty {
                ContentUnavailableView("No clusters yet", systemImage: "square.grid.3x3")
            } else {
                let idx = min(model.activeClusterIndex, clusters.count - 1)
                let cluster = clusters[idx]
                HStack {
                    Text("Cluster \(idx + 1)/\(clusters.count)")
                        .font(.headline)
                    Text("· \(cluster.label)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Prev") { model.previousCluster() }
                    Button("Next") { model.advanceCluster() }
                }
                .padding()

                if let heroID = cluster.heroID,
                   let photo = model.project?.photos.first(where: { $0.id == heroID }),
                   let project = model.project {
                    SoftPreviewView(
                        photo: photo,
                        projectName: project.name,
                        baseline: project.profile,
                        offsets: model.globalAdjustments,
                        mix: model.showBefore ? 0 : model.softRender.mix,
                        showBefore: model.showBefore
                    )
                    .frame(maxHeight: 360)
                    .padding()
                    .onAppear { model.selectPhoto(photo.id) }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cluster.photoIDs, id: \.self) { id in
                            if let photo = model.project?.photos.first(where: { $0.id == id }) {
                                Button {
                                    model.selectPhoto(id)
                                } label: {
                                    RelatedThumb(path: photo.displayThumbPath, selected: model.selectedPhotoID == id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
        }
    }
}

private struct RelatedThumb: View {
    let path: String?
    let selected: Bool

    var body: some View {
        Group {
            if let path, let img = NSImage(contentsOf: URL(fileURLWithPath: path)) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 80, height: 60)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
    }
}
