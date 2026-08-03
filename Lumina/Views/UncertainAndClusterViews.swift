import SwiftUI

enum CanvasPosture: Equatable {
    case burst
    case compare
    case single
}

struct DerivedSessionView: View {
    @Bindable var model: ProjectViewModel
    @State private var searchText = ""
    @State private var titleProjectName: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            HStack(spacing: 0) {
                SetRail(model: model)
                    .frame(width: 72)
                Divider()
                SessionCanvasHost(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ReceiptLine(model: model)
        }
        .overlay {
            overlaySlot
        }
        .onAppear {
            titleProjectName = model.project?.name
        }
        .onChange(of: model.project?.name) { _, name in
            titleProjectName = name
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLuminaSearch)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissLuminaTitle)) { _ in
            titleProjectName = nil
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if titleProjectName != nil { titleProjectName = nil }
            }
        )
    }

    private var topStrip: some View {
        HStack(spacing: 10) {
            Text(model.project?.name ?? "Lumina")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(model.cursorPosition)/\(max(model.totalCount, 1))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            TextField("⌘K Search filenames", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .frame(width: 240)
                .onSubmit {
                    guard let match = model.project?.photos.first(where: {
                        $0.filename.localizedCaseInsensitiveContains(searchText)
                    }) else { return }
                    model.setCursor(match.id)
                    model.lens = nil
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.bar)
    }

    @ViewBuilder
    private var overlaySlot: some View {
        if let error = model.userFacingError {
            ErrorCard(message: error) {
                model.userFacingError = nil
            }
        } else if let titleProjectName {
            TitleCard(projectName: titleProjectName, tastePortrait: model.tasteSummaryText) {
                self.titleProjectName = nil
            }
        } else if model.showExportPayoff, let payoff = model.exportPayoff {
            ExportPayoffSheet(payoff: payoff) {
                model.showExportPayoff = false
                if model.isCatalogMode { model.advanceCatalogQueueAfterExport() }
            }
            .frame(maxWidth: 680, maxHeight: 520)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 24)
            .padding(32)
        }
    }
}

private struct ErrorCard: View {
    let message: String
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title)
            Text(message)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Dismiss", action: dismiss)
                .buttonStyle(LuminaPrimaryButtonStyle())
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }
}

private struct SessionCanvasHost: View {
    @Bindable var model: ProjectViewModel

    private var canvasPhotos: [PhotoRecord] {
        guard let photos = model.project?.photos, let current = model.selectedPhoto else { return [] }
        if let burst = current.burstID {
            let siblings = photos.filter { $0.burstID == burst }
            if siblings.count > 1 { return siblings }
        }
        if current.uncertaintyKind == .cullTie, let cluster = current.clusterID {
            return photos.filter { $0.clusterID == cluster }
        }
        return [current]
    }

    private var posture: CanvasPosture {
        model.selectedPhoto.map(model.posture(for:)) ?? .single
    }

    private var comparePhoto: PhotoRecord? {
        guard posture == .compare else { return nil }
        return canvasPhotos.first { $0.id != model.cursor }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 1) {
                SpeedBrowseViewer(
                    model: model,
                    photos: model.project?.photos ?? [],
                    filmstripPhotos: canvasPhotos,
                    selection: Binding(get: { model.cursor }, set: { model.cursor = $0 })
                )
                if let comparePhoto {
                    SpineAwarePhotoTile(photo: comparePhoto, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                        .contentShape(Rectangle())
                        .onTapGesture { model.setCursor(comparePhoto.id) }
                }
            }

            switch model.lens {
            case .grid:
                GridOverviewView(model: model)
                    .background(.black.opacity(0.96))
            case .audit(let reason):
                AuditPileView(model: model, reason: reason)
                    .background(.black.opacity(0.96))
            case nil:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SetRail: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(model.reviewClusters.enumerated()), id: \.element.id) { index, set in
                    let members = members(for: set)
                    Button {
                        model.jumpToSet(at: index)
                    } label: {
                        VStack(spacing: 4) {
                            if let photo = members.first {
                                SpineAwarePhotoTile(photo: photo)
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Circle()
                                .fill(color(for: state(set, members: members)))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(state(set, members: members).label)
                }
            }
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .onAppear { model.warmBrowseSpine() }
    }

    private func members(for set: PhotoCluster) -> [PhotoRecord] {
        let ids = Set(set.photoIDs)
        return model.project?.photos.filter { ids.contains($0.id) } ?? []
    }

    private func state(_ set: PhotoCluster, members: [PhotoRecord]) -> RailState {
        if set.photoIDs.contains(model.cursor ?? UUID()) { return .active }
        if members.allSatisfy({ $0.tier != .unranked && !$0.isFlagged }) { return .done }
        guard let current = model.currentCluster,
              let currentIndex = model.reviewClusters.firstIndex(where: { $0.id == current.id }),
              let setIndex = model.reviewClusters.firstIndex(where: { $0.id == set.id }) else {
            return .settled
        }
        return setIndex > currentIndex ? .ahead : .settled
    }

    private func color(for state: RailState) -> Color {
        switch state {
        case .ahead: .orange
        case .settled: .secondary
        case .active: .accentColor
        case .done: .green
        }
    }
}

private enum RailState {
    case ahead, settled, active, done

    var label: String {
        switch self {
        case .ahead: "Ahead"
        case .settled: "Settled"
        case .active: "Active"
        case .done: "Done"
        }
    }
}

private struct ReceiptLine: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        HStack(spacing: 12) {
            if model.isCatalogMode {
                Text("Folder \((model.catalogQueue.activeFolderIndex ?? 0) + 1)/\(model.catalogQueue.totalFolders)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(model.receiptText)
                .font(.caption.monospacedDigit())
            Spacer()
            ForEach(model.auditPiles) { pile in
                Button("\(pile.reason.title) \(pile.photos.count)") {
                    model.lens = .audit(pile.reason)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            Button("Grid") { model.lens = .grid }
                .buttonStyle(.plain)
                .font(.caption)
            Button("Export") { model.exportCarousel() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .disabled(model.keepCount == 0)
            Text(model.keymapHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.bar)
    }
}

private struct AuditPileView: View {
    @Bindable var model: ProjectViewModel
    let reason: AuditReason
    @State private var rescuedIDs: Set<PhotoID> = []
    @State private var reviewedIDs: Set<PhotoID> = []

    private var pile: AuditPile? {
        model.auditPiles.first { $0.reason == reason }
    }

    private var columns: [GridItem] {
        if requiresIndividualReview {
            return [GridItem(.flexible(minimum: 480), spacing: 8)]
        }
        let minimum: CGFloat = reason == .cullTie ? 118 : (reason == .hardReject ? 210 : 160)
        return [GridItem(.adaptive(minimum: minimum), spacing: 8)]
    }

    private var requiresIndividualReview: Bool {
        guard let metrics = model.auditMetrics[reason], metrics.proposed > 0 else { return false }
        return metrics.rescueRate > 0.10
    }

    private var canAccept: Bool {
        !requiresIndividualReview || reviewedIDs.count >= (pile?.photos.count ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close") { model.lens = nil }
                    .buttonStyle(LuminaPressStyle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(reason.title).font(.headline)
                    Text(requiresIndividualReview
                        ? "High prior rescue rate · inspect every frame before accepting."
                        : "P rescues the focused exception · Return accepts every other proposal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(rescuedIDs.count) rescued")
                    .font(.caption.monospacedDigit())
                if let metrics = model.auditMetrics[reason], metrics.proposed > 0 {
                    Text("\(metrics.rescueRate.formatted(.percent.precision(.fractionLength(1)))) prior rescue")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            metrics.rescueRate > 0.10 || metrics.rescueRate < 0.01 ? .orange : .secondary
                        )
                }
                Button("Accept pile") {
                    model.acceptPile(reason, rescuedIDs: rescuedIDs)
                    rescuedIDs.removeAll()
                }
                .buttonStyle(LuminaPrimaryButtonStyle())
                .disabled(!canAccept)
            }
            .padding(12)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(pile?.photos ?? []) { photo in
                        Button {
                            model.setCursor(photo.id)
                            if rescuedIDs.contains(photo.id) {
                                rescuedIDs.remove(photo.id)
                            } else {
                                rescuedIDs.insert(photo.id)
                            }
                        } label: {
                            SpineAwarePhotoTile(photo: photo)
                                .aspectRatio(reason == .cullTie ? 1 : 4 / 3, contentMode: .fill)
                                .clipped()
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(rescuedIDs.contains(photo.id) ? Color.green : (
                                            model.cursor == photo.id ? Color.accentColor : .clear
                                        ), lineWidth: rescuedIDs.contains(photo.id) ? 4 : 2)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .onAppear {
            if let cursor = model.cursor,
               pile?.photos.contains(where: { $0.id == cursor }) == true {
                reviewedIDs.insert(cursor)
            } else if let first = pile?.photos.first {
                model.setCursor(first.id)
                reviewedIDs.insert(first.id)
            }
        }
        .onChange(of: model.cursor) { _, cursor in
            guard let cursor, pile?.photos.contains(where: { $0.id == cursor }) == true else { return }
            reviewedIDs.insert(cursor)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLuminaAuditRescue)) { _ in
            guard let cursor = model.cursor,
                  pile?.photos.contains(where: { $0.id == cursor }) == true else { return }
            if rescuedIDs.contains(cursor) {
                rescuedIDs.remove(cursor)
            } else {
                rescuedIDs.insert(cursor)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .acceptLuminaAuditPile)) { _ in
            guard canAccept else { return }
            model.acceptPile(reason, rescuedIDs: rescuedIDs)
            rescuedIDs.removeAll()
        }
    }
}

private struct TitleCard: View {
    let projectName: String
    let tastePortrait: String
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(projectName)
                .font(.largeTitle.weight(.semibold))
            Text(tastePortrait)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("P keep · X cut · M audit · F/D move")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
        .onTapGesture(perform: dismiss)
        .transition(.opacity)
    }
}
