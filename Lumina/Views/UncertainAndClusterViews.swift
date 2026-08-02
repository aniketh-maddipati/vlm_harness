import SwiftUI
import AppKit

/// Single session spine: Meet → Pick → Decide → Export.
struct SessionSpineView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        let clusters = model.reviewClusters
        VStack(spacing: 0) {
            sessionChrome(clusterCount: clusters.count)

            if model.sessionPhase == .export {
                ExportPhaseView(model: model)
            } else if clusters.isEmpty {
                ContentUnavailableView("No sets yet", systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let idx = min(model.activeClusterIndex, clusters.count - 1)
                let cluster = clusters[idx]
                let members = clusterMembers(cluster)

                Group {
                    switch model.sessionPhase {
                    case .meet:
                        GroupIntroPhase(cluster: cluster, members: members) {
                            model.advanceFromMeet()
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
                        GroupDecidePhase(model: model, cluster: cluster)
                    case .export:
                        EmptyView()
                    }
                }
                .animation(.easeInOut(duration: 0.32), value: model.sessionPhase)
                .id("\(cluster.id)-\(model.sessionPhase.rawValue)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionChrome(clusterCount: Int) -> some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    phasePill("Meet", active: model.sessionPhase == .meet)
                    chevron
                    phasePill("Pick", active: model.sessionPhase == .pick)
                    chevron
                    phasePill("Decide", active: model.sessionPhase == .decide)
                    chevron
                    phasePill("Export", active: model.sessionPhase == .export)
                    if model.sessionPhase != .export, clusterCount > 0 {
                        Text("Set \(min(model.activeClusterIndex + 1, clusterCount)) / \(clusterCount)")
                            .font(.headline.monospacedDigit())
                            .padding(.leading, 8)
                    }
                }
                .padding(.vertical, 2)
            }

            if clusterCount > 0, model.sessionPhase != .export {
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

// Back-compat name used by older references.
typealias ClusterCullView = SessionSpineView

// MARK: - Meet

private struct GroupIntroPhase: View {
    let cluster: PhotoCluster
    let members: [PhotoRecord]
    let onContinue: () -> Void

    @State private var appear = false

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

            ProgressivePhotoWall(
                paths: members.compactMap { $0.gridThumbPath ?? $0.thumbPath },
                maxSlots: members.count,
                revealIntervalMs: 360,
                prefetchAhead: 4
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 16)

            Text("\(members.count) photos · filling in as previews land")
                .font(.body)
                .foregroundStyle(.tertiary)

            Button(action: onContinue) {
                Text("Pick from this set")
                    .frame(minWidth: 200)
            }
            .buttonStyle(LuminaPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            logMeetGridMissingThumbPaths(members)
            ThumbCache.shared.prefetchPhotos(members, maxPixelSize: 512)
            withAnimation(.spring(duration: 0.65, bounce: 0.14)) { appear = true }
        }
    }
}

private func logMeetGridMissingThumbPaths(_ members: [PhotoRecord]) {
    for member in members where member.gridThumbPath == nil && member.thumbPath == nil {
        let reason: String
        if member.previewLongEdge == 0, member.previewOrigin == .unknown {
            reason = "preview not yet generated (previewLongEdge=0, previewOrigin=unknown)"
        } else if member.previewLongEdge > 0 {
            reason = "preview metadata present but thumb paths missing (previewLongEdge=\(member.previewLongEdge), previewOrigin=\(member.previewOrigin.rawValue))"
        } else {
            reason = "thumb paths unset (previewOrigin=\(member.previewOrigin.rawValue))"
        }
        print("[MeetGrid] Missing thumb path for photo id=\(member.id) filename=\"\(member.filename)\" gridThumbPath=nil thumbPath=nil — \(reason)")
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
                Text("Tap to keep — unselected go to Decide if borderline")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 10)

            ProgressivePickWall(
                photos: members,
                selected: selected,
                onToggle: onToggle,
                revealIntervalMs: 280,
                batchSize: 2
            )
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

// MARK: - Decide (uncertain + flagged bridged as leftovers)

private struct GroupDecidePhase: View {
    @Bindable var model: ProjectViewModel
    let cluster: PhotoCluster

    var body: some View {
        let leftovers = model.decideLeftovers(in: cluster)

        Group {
            if leftovers.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ContentUnavailableView(
                        "Nothing left to decide",
                        systemImage: "checkmark.circle",
                        description: Text("Continue to the next set.")
                    )
                    Button("Next set →") { model.advanceCluster() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
            } else {
                SpeedBrowseViewer(
                    model: model,
                    photos: leftovers,
                    selection: $model.selectedPhotoID
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if let first = leftovers.first {
                model.selectBrowsePhoto(first.id, in: leftovers, inputTime: CFAbsoluteTimeGetCurrent())
            }
        }
    }
}

// MARK: - Export

struct ExportPhaseView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        let keeps = model.project?.photos.filter { $0.tier == .keep }
            .sorted { $0.cullScore > $1.cullScore } ?? []

        VStack(spacing: 16) {
            Spacer(minLength: 12)
            Text("Session clear")
                .font(.largeTitle.weight(.semibold))
            Text("\(keeps.count) keeps · export?")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(model.tasteSummaryText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !keeps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(keeps.prefix(12))) { photo in
                            GradedCompareView(
                                mode: .single(photo),
                                projectName: model.project?.name ?? "",
                                recipeFor: { model.appliedRecipe(for: $0) },
                                mix: .constant(1),
                                showBefore: false
                            )
                            .frame(width: 120, height: 150)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 160)
            }

            Button("Export") { model.exportCarousel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

            Button("Grid overview") { model.openGridOverview() }
                .buttonStyle(LuminaPressStyle())

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

typealias SessionDoneView = ExportPhaseView

struct UncertainQueueView: View {
    @Bindable var model: ProjectViewModel
    var body: some View { SessionSpineView(model: model) }
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
