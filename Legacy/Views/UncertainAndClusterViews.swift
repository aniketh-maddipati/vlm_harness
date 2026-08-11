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
        HStack(spacing: 12) {
            Text(model.project?.name ?? "Lumina")
                .font(LuminaAtmosphere.Typeface.body(13).weight(.medium))
                .foregroundStyle(Color.primary.opacity(0.78))
                .lineLimit(1)
            Text("\(model.cursorPosition) / \(max(model.totalCount, 1))")
                .font(LuminaAtmosphere.Typeface.caption(11).monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.7))
            Spacer()
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .frame(width: 180)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05), in: Capsule())
                .onSubmit {
                    guard let match = model.project?.photos.first(where: {
                        $0.filename.localizedCaseInsensitiveContains(searchText)
                    }) else { return }
                    model.setCursor(match.id)
                    model.lens = nil
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color.black.opacity(0.02))
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
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
            .animation(LuminaAtmosphere.Motion.bloom, value: model.showExportPayoff)
        }
    }
}

private struct ErrorCard: View {
    let message: String
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(LuminaAtmosphere.Typeface.body(15))
                .foregroundStyle(Color.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Dismiss", action: dismiss)
                .buttonStyle(LuminaGhostButtonStyle())
        }
        .padding(28)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
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
                    .background(LuminaAtmosphere.void.opacity(0.97))
                    .transition(.opacity)
            case .audit(let reason):
                AuditPileView(model: model, reason: reason)
                    .background(LuminaAtmosphere.void.opacity(0.97))
                    .transition(.opacity)
            case nil:
                EmptyView()
            }
        }
        .animation(LuminaAtmosphere.Motion.settle, value: model.lens != nil)
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
        .background(Color.primary.opacity(0.03))
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
        case .ahead: LuminaAtmosphere.breath
        case .settled: Color.secondary.opacity(0.45)
        case .active: LuminaAtmosphere.affirm
        case .done: Color.white.opacity(0.22)
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
        HStack(spacing: 14) {
            if model.isCatalogMode {
                Text("Folder \((model.catalogQueue.activeFolderIndex ?? 0) + 1)/\(model.catalogQueue.totalFolders)")
                    .font(LuminaAtmosphere.Typeface.caption(11).monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            Text(model.receiptText)
                .font(LuminaAtmosphere.Typeface.caption(11).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            ForEach(model.auditPiles) { pile in
                Button("\(pile.reason.title) · \(pile.photos.count)") {
                    model.lens = .audit(pile.reason)
                }
                .buttonStyle(.plain)
                .font(LuminaAtmosphere.Typeface.caption(11))
                .foregroundStyle(LuminaAtmosphere.affirm.opacity(0.9))
            }
            Button("Grid") { model.lens = .grid }
                .buttonStyle(.plain)
                .font(LuminaAtmosphere.Typeface.caption(11))
                .foregroundStyle(.secondary)
            Button("Publish") { model.exportCarousel() }
                .buttonStyle(.plain)
                .font(LuminaAtmosphere.Typeface.caption(11).weight(.medium))
                .foregroundStyle(Color.primary.opacity(model.keepCount == 0 ? 0.28 : 0.85))
                .disabled(model.keepCount == 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(Color.black.opacity(0.02))
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
            HStack(spacing: 16) {
                Button("Back") { model.lens = nil }
                    .buttonStyle(LuminaGhostButtonStyle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(reason.title)
                        .font(LuminaAtmosphere.Typeface.display(22))
                        .foregroundStyle(Color.white.opacity(0.92))
                    Text(requiresIndividualReview
                        ? "These needed you before — glance each one."
                        : "Rescue exceptions. Accept the rest.")
                        .font(LuminaAtmosphere.Typeface.caption(12))
                        .foregroundStyle(LuminaAtmosphere.whisper)
                }
                Spacer()
                if rescuedIDs.count > 0 {
                    Text("\(rescuedIDs.count) kept close")
                        .font(LuminaAtmosphere.Typeface.caption(11).monospacedDigit())
                        .foregroundStyle(LuminaAtmosphere.breath)
                }
                Button("Accept remaining") {
                    model.acceptPile(reason, rescuedIDs: rescuedIDs)
                    rescuedIDs.removeAll()
                }
                .buttonStyle(LuminaPrimaryButtonStyle())
                .disabled(!canAccept)
                .opacity(canAccept ? 1 : 0.45)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
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
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(
                                            rescuedIDs.contains(photo.id)
                                                ? LuminaAtmosphere.affirm
                                                : (model.cursor == photo.id
                                                    ? Color.white.opacity(0.55)
                                                    : Color.clear),
                                            lineWidth: rescuedIDs.contains(photo.id) ? 1.5 : 1
                                        )
                                }
                                .opacity(rescuedIDs.contains(photo.id) ? 1 : 0.82)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
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
        VStack(spacing: 12) {
            Text(projectName)
                .font(LuminaAtmosphere.Typeface.display(28))
                .foregroundStyle(Color.white.opacity(0.94))
            if !tastePortrait.isEmpty {
                Text(tastePortrait)
                    .font(LuminaAtmosphere.Typeface.body(14))
                    .foregroundStyle(LuminaAtmosphere.whisper)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            Text("P keep · X cut · M when unsure · F/D move")
                .font(LuminaAtmosphere.Typeface.caption(12))
                .foregroundStyle(LuminaAtmosphere.breath)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .onTapGesture(perform: dismiss)
        .transition(.opacity)
    }
}
