import SwiftUI
import AppKit

/// Directed iPad-style session: Meet set → Pick → Decide leftovers → next set → Done.
struct ClusterCullView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        let clusters = model.reviewClusters
        VStack(spacing: 0) {
            sessionChrome(clusterCount: clusters.count)

            if model.groupPhase == .done {
                SessionDoneView(model: model)
            } else if clusters.isEmpty {
                ContentUnavailableView("No sets yet", systemImage: "rectangle.stack")
            } else {
                let idx = min(model.activeClusterIndex, clusters.count - 1)
                let cluster = clusters[idx]
                let members = clusterMembers(cluster)

                Group {
                    switch model.groupPhase {
                    case .intro:
                        GroupIntroPhase(cluster: cluster, members: members) {
                            withAnimation(.easeInOut(duration: 0.32)) {
                                model.groupPhase = .pick
                                model.seedPickFromHero(cluster: cluster)
                            }
                        }
                    case .pick:
                        GroupPickPhase(
                            cluster: cluster,
                            members: members,
                            selected: model.manualPickIDs,
                            onToggle: { model.toggleManualPick($0) },
                            onConfirm: { model.confirmPicksAndAdvance(cluster: cluster) },
                            onSkip: { model.skipPicksUseModel(cluster: cluster) }
                        )
                    case .decide:
                        GroupDecidePhase(model: model, cluster: cluster, members: members)
                    case .done:
                        EmptyView()
                    }
                }
                .animation(.easeInOut(duration: 0.32), value: model.groupPhase)
                .id("\(cluster.id)-\(model.groupPhase)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func sessionChrome(clusterCount: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                phasePill("Meet", active: model.groupPhase == .intro)
                chevron
                phasePill("Pick", active: model.groupPhase == .pick)
                chevron
                phasePill("Decide", active: model.groupPhase == .decide)
                chevron
                phasePill("Done", active: model.groupPhase == .done)
                Spacer()
                if model.groupPhase != .done, clusterCount > 0 {
                    Text("Set \(min(model.activeClusterIndex + 1, clusterCount)) / \(clusterCount)")
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
            }

            // Progress through sets
            if clusterCount > 0, model.groupPhase != .done {
                GeometryReader { geo in
                    let t = CGFloat(model.activeClusterIndex) / CGFloat(max(clusterCount, 1))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: max(8, geo.size.width * t))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func phasePill(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(active ? .bold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(active ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08), in: Capsule())
    }

    private func clusterMembers(_ cluster: PhotoCluster) -> [PhotoRecord] {
        guard let photos = model.project?.photos else { return [] }
        let map = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        return cluster.photoIDs.compactMap { map[$0] }
    }
}

// MARK: - Meet

private struct GroupIntroPhase: View {
    let cluster: PhotoCluster
    let members: [PhotoRecord]
    let onContinue: () -> Void

    @State private var appear = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            Text(cluster.label)
                .font(.largeTitle.weight(.semibold))
                .opacity(appear ? 1 : 0)

            Text(cluster.whyGrouped)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .opacity(appear ? 1 : 0)

            // Large hero + fan of peers
            ZStack {
                ForEach(Array(members.prefix(6).enumerated()), id: \.element.id) { index, photo in
                    LargeThumb(path: photo.displayThumbPath, size: CGSize(width: 280, height: 210))
                        .rotationEffect(.degrees(Double(index) * 3.5 - 8))
                        .offset(
                            x: appear ? CGFloat(index - 2) * 42 : 0,
                            y: appear ? CGFloat(abs(index - 2)) * 8 : 28
                        )
                        .opacity(appear ? 1 : 0)
                        .zIndex(Double(6 - index))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                }
            }
            .frame(height: 260)
            .padding(.vertical, 12)

            Text("\(members.count) photos in this set · pick the ones you want next")
                .font(.body)
                .foregroundStyle(.tertiary)

            Button(action: onContinue) {
                Text("Review this set")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.16)) { appear = true }
        }
    }
}

// MARK: - Pick

private struct GroupPickPhase: View {
    let cluster: PhotoCluster
    let members: [PhotoRecord]
    let selected: Set<UUID>
    let onToggle: (UUID) -> Void
    let onConfirm: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pick your set")
                    .font(.title2.weight(.semibold))
                Text(cluster.whyGrouped)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Tap to keep. Large cards so you can actually see faces and sharpness.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(members) { photo in
                        Button {
                            onToggle(photo.id)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack(alignment: .topTrailing) {
                                    LargeThumb(
                                        path: photo.displayThumbPath,
                                        size: CGSize(width: 300, height: 225)
                                    )
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(4 / 3, contentMode: .fit)

                                    Image(systemName: selected.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, selected.contains(photo.id) ? Color.accentColor : .white.opacity(0.5))
                                        .padding(10)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selected.contains(photo.id) ? Color.accentColor : .clear, lineWidth: 3)
                                )

                                HStack {
                                    Text(photo.filename)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.2f", photo.cullScore))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack {
                Button("Use model picks") { onSkip() }
                    .controlSize(.large)
                Spacer()
                Text("\(selected.count) selected")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Keep these →") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selected.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Decide

private struct GroupDecidePhase: View {
    @Bindable var model: ProjectViewModel
    let cluster: PhotoCluster
    let members: [PhotoRecord]

    var body: some View {
        let leftovers = model.uncertainInCluster(cluster)
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(leftovers.isEmpty ? "Set clear" : "Close calls")
                        .font(.title2.weight(.semibold))
                    Text(cluster.whyGrouped)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if leftovers.isEmpty {
                    Button("Next set →") { model.advanceCluster() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Text("\(leftovers.count) left")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 20)

            if leftovers.isEmpty {
                ContentUnavailableView(
                    "Nice — nothing uncertain here",
                    systemImage: "checkmark.circle",
                    description: Text("Continue to the next set.")
                )
            } else if let photo = model.selectedPhoto,
                      let project = model.project {
                SoftPreviewView(
                    photo: photo,
                    projectName: project.name,
                    baseline: project.profile,
                    offsets: model.globalAdjustments,
                    mix: model.showBefore ? 0 : model.softRender.mix,
                    showBefore: model.showBefore
                )
                .frame(maxHeight: 480)
                .padding(.horizontal, 20)

                Text(photo.whySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(leftovers) { p in
                            Button { model.selectPhoto(p.id) } label: {
                                LargeThumb(
                                    path: p.displayThumbPath,
                                    size: CGSize(width: 160, height: 120),
                                    selected: model.selectedPhotoID == p.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                HStack(spacing: 20) {
                    Button("Reject (X)") { model.markReject() }
                        .controlSize(.large)
                    Button("Hero") { model.markHero() }
                        .controlSize(.large)
                    Button("Keep (P)") { model.markKeep() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                .padding(.bottom, 10)
            }

            // Full set context strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(members) { photo in
                        LargeThumb(
                            path: photo.displayThumbPath,
                            size: CGSize(width: 96, height: 72),
                            selected: model.selectedPhotoID == photo.id
                        )
                        .opacity(photo.tier == .reject ? 0.35 : 1)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if let first = leftovers.first {
                model.selectPhoto(first.id)
            }
        }
    }
}

// MARK: - Done

private struct SessionDoneView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        let keeps = model.project?.photos.filter { $0.tier == .keep }
            .sorted { $0.cullScore > $1.cullScore } ?? []

        VStack(spacing: 20) {
            Spacer(minLength: 20)
            Text("Session clear")
                .font(.largeTitle.weight(.semibold))
            Text("\(keeps.count) keeps · ready to export")
                .font(.title2)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(keeps.prefix(16)) { photo in
                        LargeThumb(
                            path: photo.displayThumbPath,
                            size: CGSize(width: 200, height: 150)
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
            .frame(height: 170)

            Button("Export collections") {
                model.exportCarousel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Button("Browse all keeps") {
                model.viewMode = .overview
            }
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Legacy uncertain (used only if overview needs it)

struct UncertainQueueView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        ClusterCullView(model: model)
            .onAppear {
                model.viewMode = .session
                model.groupPhase = .decide
            }
    }
}

// MARK: - Thumbs

struct LargeThumb: View {
    let path: String?
    var size: CGSize = CGSize(width: 200, height: 150)
    var selected: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
            if let path, let img = NSImage(contentsOf: URL(fileURLWithPath: path)) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.accentColor : .clear, lineWidth: 3)
        )
    }
}

/// Back-compat alias
typealias RelatedThumb = LargeThumb
