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
                .animation(.easeInOut(duration: 0.22), value: model.sessionPhase)
                .id("\(cluster.id)-\(model.sessionPhase.rawValue)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(setSwipeGesture(clusterCount: clusters.count))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionChrome(clusterCount: Int) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                phasePill("Meet", active: model.sessionPhase == .meet)
                phasePill("Pick", active: model.sessionPhase == .pick)
                phasePill("Decide", active: model.sessionPhase == .decide)
                phasePill("Export", active: model.sessionPhase == .export)
            }

            Spacer(minLength: 8)

            if model.sessionPhase != .export, clusterCount > 0 {
                Text("Set \(min(model.activeClusterIndex + 1, clusterCount))/\(clusterCount)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    model.previousCluster()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 40, height: 36)
                }
                .buttonStyle(LuminaPressStyle())
                .disabled(model.activeClusterIndex <= 0)

                Button {
                    model.advanceCluster()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .frame(width: 40, height: 36)
                }
                .buttonStyle(LuminaPressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            if clusterCount > 0, model.sessionPhase != .export {
                GeometryReader { geo in
                    let progress = CGFloat(model.activeClusterIndex + 1) / CGFloat(max(clusterCount, 1))
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.secondary.opacity(0.12))
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: max(6, geo.size.width * progress))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func phasePill(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.caption.weight(active ? .bold : .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(active ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08), in: Capsule())
    }

    private func setSwipeGesture(clusterCount: Int) -> some Gesture {
        DragGesture(minimumDistance: 48)
            .onEnded { value in
                guard clusterCount > 1 else { return }
                // Prefer horizontal swipes for set navigation.
                guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                if value.translation.width < -56 {
                    model.advanceCluster()
                } else if value.translation.width > 56 {
                    model.previousCluster()
                }
            }
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

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cluster.label)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Text(cluster.whyGrouped)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text("\(members.count)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                Text(members.count == 1 ? "photo" : "photos")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            SessionPhotoGrid(photos: members)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onContinue) {
                Text("Pick from this set")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(LuminaPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            logMeetGridMissingThumbPaths(members)
            PreviewSpine.shared.warm(photos: members, focus: members.first?.id)
            ThumbCache.shared.prefetchPhotos(members, maxPixelSize: 512)
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pick your keepers")
                        .font(.title3.weight(.semibold))
                    Text("Tap to keep · \(members.count) in this set")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(selected.count)")
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(selected.isEmpty ? .secondary : Color.accentColor)
                Text("selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            ProgressivePickWall(
                photos: members,
                selected: selected,
                onToggle: onToggle
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LuminaFooterBar {
                Button {
                    onSkip()
                } label: {
                    Text("Use model picks")
                        .font(.headline)
                        .frame(minWidth: 140, minHeight: 44)
                }
                .buttonStyle(LuminaPressStyle())

                Spacer()

                Button {
                    onConfirm()
                } label: {
                    Text("Keep these →")
                        .frame(minWidth: 160)
                        .frame(height: 48)
                }
                .buttonStyle(LuminaPrimaryButtonStyle())
                .disabled(selected.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            PreviewSpine.shared.warm(photos: members, focus: members.first?.id)
            ThumbCache.shared.prefetchPhotos(members, maxPixelSize: 512)
        }
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
                VStack(spacing: 18) {
                    Spacer()
                    ContentUnavailableView(
                        "Nothing left to decide",
                        systemImage: "checkmark.circle",
                        description: Text("Continue to the next set.")
                    )
                    Button {
                        model.advanceCluster()
                    } label: {
                        Text("Next set →")
                            .frame(minWidth: 180)
                            .frame(height: 48)
                    }
                    .buttonStyle(LuminaPrimaryButtonStyle())
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    if leftovers.count == 1 {
                        Text("1 close call left")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    SpeedBrowseViewer(
                        model: model,
                        photos: leftovers,
                        selection: $model.selectedPhotoID
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            ThumbCache.shared.prefetchPhotos(leftovers, maxPixelSize: 512)
            PreviewSpine.shared.warm(photos: leftovers, focus: leftovers.first?.id)
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

        VStack(spacing: 14) {
            Spacer(minLength: 8)
            Text("Session clear")
                .font(.title.weight(.semibold))
            Text("\(keeps.count) keeps · export?")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(model.tasteSummaryText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if !keeps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(keeps.prefix(12))) { photo in
                            SpineAwarePhotoTile(photo: photo)
                                .frame(width: 96, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .frame(height: 128)
            }

            Button {
                model.exportCarousel()
            } label: {
                Text("Export")
                    .frame(minWidth: 200)
                    .frame(height: 48)
            }
            .buttonStyle(LuminaPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)

            Button("Grid overview") { model.openGridOverview() }
                .buttonStyle(LuminaPressStyle())
                .font(.headline)
                .frame(minHeight: 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            ThumbCache.shared.prefetchPhotos(Array(keeps.prefix(24)), maxPixelSize: 512)
            PreviewSpine.shared.warm(photos: Array(keeps.prefix(24)), focus: keeps.first?.id)
        }
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
        Group {
            if let photo {
                SpineAwarePhotoTile(photo: photo, contentMode: .fit)
            } else {
                PhotoImageView(photo: nil, path: path, tier: tier, contentMode: .fit)
            }
        }
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
