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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionChrome(clusterCount: Int) -> some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    phasePill("Meet", active: model.groupPhase == .intro)
                    chevron
                    phasePill("Pick", active: model.groupPhase == .pick)
                    chevron
                    phasePill("Decide", active: model.groupPhase == .decide)
                    chevron
                    phasePill("Done", active: model.groupPhase == .done)
                    if model.groupPhase != .done, clusterCount > 0 {
                        Text("Set \(min(model.activeClusterIndex + 1, clusterCount)) / \(clusterCount)")
                            .font(.headline.monospacedDigit())
                            .padding(.leading, 8)
                    }
                }
                .padding(.vertical, 2)
            }

            if clusterCount > 0, model.groupPhase != .done {
                GeometryReader { geo in
                    let progress = CGFloat(model.activeClusterIndex + 1) / CGFloat(max(clusterCount, 1))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: max(8, geo.size.width * progress))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
    @State private var focusedID: UUID?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(cluster.label)
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .opacity(appear ? 1 : 0)

                Text(cluster.whyGrouped)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .opacity(appear ? 1 : 0)
            }
            .padding(.top, 8)

            FloatingPhotoCarousel(
                items: members,
                selection: $focusedID,
                itemID: \.id,
                spacing: 30,
                peek: 5,
                onSelectionChange: { photo in
                    Task {
                        await PhotoImageCache.shared.prefetch([
                            photo.previewPath,
                            photo.sharpPath
                        ].compactMap { $0 })
                    }
                }
            ) { photo, centered in
                FloatingPhotoCard(photo: photo, centered: centered)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .frame(maxHeight: 340)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 24)

            Text("\(members.count) photos · scroll sideways, then review")
                .font(.body)
                .foregroundStyle(.tertiary)

            Button(action: onContinue) {
                Text("Review this set")
                    .frame(minWidth: 200)
            }
            .buttonStyle(LuminaPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            focusedID = members.first?.id
            withAnimation(.spring(duration: 0.65, bounce: 0.14)) { appear = true }
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
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pick your set")
                    .font(.title2.weight(.semibold))
                Text(cluster.whyGrouped)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Tap to keep")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 10)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(members) { photo in
                        PickCard(
                            photo: photo,
                            selected: selected.contains(photo.id),
                            onToggle: { onToggle(photo.id) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LuminaFooterBar {
                Button("Use model picks") { onSkip() }
                    .buttonStyle(LuminaPressStyle())
                Spacer()
                Text("\(selected.count) selected")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Keep these →") { onConfirm() }
                    .buttonStyle(LuminaPrimaryButtonStyle())
                    .disabled(selected.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PickCard: View {
    let photo: PhotoRecord
    let selected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    PhotoImageView(photo: photo, tier: .preview, contentMode: .fit)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, selected ? Color.accentColor : .white.opacity(0.45))
                        .padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 3 : 1)
                )

                Text(photo.filename)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .buttonStyle(LuminaPressStyle(pressedScale: 0.97))
    }
}

// MARK: - Decide

private struct GroupDecidePhase: View {
    @Bindable var model: ProjectViewModel
    let cluster: PhotoCluster
    let members: [PhotoRecord]

    var body: some View {
        let leftovers = model.uncertainInCluster(cluster)

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(leftovers.isEmpty ? "Set clear" : "Close calls")
                        .font(.title2.weight(.semibold))
                    Text(leftovers.isEmpty ? cluster.whyGrouped : "← → to browse · P keep · X reject")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if leftovers.isEmpty {
                    Button("Next set →") { model.advanceCluster() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("\(leftovers.count) left")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            if leftovers.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Nothing uncertain here",
                    systemImage: "checkmark.circle",
                    description: Text("Continue to the next set.")
                )
                Spacer()
            } else if leftovers.count == 2,
                      leftovers.allSatisfy({ $0.uncertaintyKind == .cullTie }),
                      let project = model.project {
                ComparePairView(
                    left: leftovers[0],
                    right: leftovers[1],
                    projectName: project.name,
                    mix: $model.compareMix,
                    selectedID: model.selectedPhotoID,
                    onSelect: { model.selectPhoto($0) }
                )
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity)

                LuminaDecisionBar(
                    onReject: { model.markReject() },
                    onHero: { model.markHero() },
                    onKeep: { model.markKeep() }
                )
                .padding(.bottom, 12)
            } else if let project = model.project {
                VStack(spacing: 14) {
                    FloatingPhotoCarousel(
                        items: leftovers,
                        selection: $model.selectedPhotoID,
                        itemID: \.id,
                        spacing: 28,
                        peek: 5,
                        onSelectionChange: { photo in
                            model.prefetchPhotoDisplay(photo)
                        }
                    ) { photo, centered in
                        Group {
                            if centered, model.selectedPhotoID == photo.id {
                                SoftPreviewView(
                                    photo: photo,
                                    projectName: project.name,
                                    displayRecipe: model.appliedRecipe(for: photo),
                                    mix: model.showBefore ? 0 : model.softRender.mix,
                                    showBefore: model.showBefore
                                )
                            } else {
                                FloatingPhotoCard(
                                    photo: photo,
                                    projectName: project.name,
                                    centered: centered
                                )
                            }
                        }
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .frame(maxHeight: 420)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)

                    if let photo = model.selectedPhoto {
                        Text(photo.whySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.horizontal, 24)
                    }

                    LuminaDecisionBar(
                        onReject: { model.markReject() },
                        onHero: { model.markHero() },
                        onKeep: { model.markKeep() }
                    )
                    .padding(.bottom, 12)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let first = leftovers.first {
                model.selectPhoto(first.id)
            }
        }
    }
}

// MARK: - Done

struct SessionDoneView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        let keeps = model.project?.photos.filter { $0.tier == .keep }
            .sorted { $0.cullScore > $1.cullScore } ?? []

        VStack(spacing: 16) {
            Spacer(minLength: 12)
            Text("Session clear")
                .font(.largeTitle.weight(.semibold))
            Text("\(keeps.count) keeps · ready to export")
                .font(.title3)
                .foregroundStyle(.secondary)

            if !keeps.isEmpty {
                FloatingPhotoCarousel(
                    items: Array(keeps.prefix(16)),
                    selection: .constant(keeps.first?.id),
                    itemID: \.id,
                    spacing: 24,
                    peek: 5
                ) { photo, centered in
                    FloatingPhotoCard(photo: photo, centered: centered)
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .frame(maxHeight: 160)
                }
                .frame(height: 180)
                .padding(.horizontal, 8)
            }

            Button("Export collections") { model.exportCarousel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

            Button("Browse all keeps") { model.enterKeepsBrowser() }
                .buttonStyle(LuminaPrimaryButtonStyle())

            if let summary = model.sessionSummary {
                Text(summary.narrative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button("Back to all sets") { model.backToStackFeed() }
                .buttonStyle(LuminaPressStyle())

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UncertainQueueView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        ClusterCullView(model: model)
    }
}

// MARK: - Thumbs

struct LargeThumb: View {
    let photo: PhotoRecord?
    let path: String?
    var width: CGFloat?
    var height: CGFloat?
    var selected: Bool = false
    var tier: PhotoImageTier = .preview

    init(path: String?, width: CGFloat? = nil, height: CGFloat? = nil, selected: Bool = false) {
        self.photo = nil
        self.path = path
        self.width = width
        self.height = height
        self.selected = selected
    }

    init(photo: PhotoRecord, tier: PhotoImageTier = .preview, width: CGFloat? = nil, height: CGFloat? = nil, selected: Bool = false) {
        self.photo = photo
        self.path = nil
        self.tier = tier
        self.width = width
        self.height = height
        self.selected = selected
    }

    var body: some View {
        PhotoImageView(photo: photo, path: path, tier: tier, contentMode: .fit)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 3)
            )
    }
}

typealias RelatedThumb = LargeThumb
