import SwiftUI

struct ElasticFilmstrip: View {
    @Bindable var session: P0SessionModel
    @State private var viewportSpace = UUID()
    @State private var viewportSnapshot = ElasticViewportSnapshot()
    @State private var revealRequest: ElasticViewportReveal.Request?

    var body: some View {
        let boundaries = ElasticChronology.boundaries(
            orderedIDs: session.stripAssetIDs, chapters: session.chapters,
            chronological: session.peek != .set
        )
        return GeometryReader { viewport in
          ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ElasticLayout.filmstripGap) {
                    if session.peek == .set {
                        chronologyLabel(session.stripLabel)
                    }

                    ForEach(session.stripAssetIDs, id: \.self) { id in
                        if let asset = session.asset(id) {
                            if let chapter = boundaries[id] {
                                chronologyLabel(ElasticChronology.label(for: chapter))
                                    .padding(.leading, ElasticLayout.filmstripMomentGap)
                            }
                            tile(asset)
                        }
                    }
                }
                .background(ElasticScrollInterruption { revealRequest = nil })
                .padding(.horizontal, ElasticLayout.tableGutter)
                .frame(height: ElasticLayout.filmstripHeight)
            }
            .coordinateSpace(name: viewportSpace)
            .environment(\.elasticViewportSpace, viewportSpace)
            .onPreferenceChange(ElasticViewportFrames.self) { snapshot in
                viewportSnapshot = snapshot
                resolveReveal(snapshot: snapshot, viewport: viewport.size, proxy: proxy)
            }
            .onAppear {
                requestReveal()
                resolveReveal(snapshot: viewportSnapshot, viewport: viewport.size, proxy: proxy)
            }
            .onChange(of: session.focusedAssetID) { _, _ in
                // Wait for the focused tile's new dimensions, not its previous small box.
                requestReveal()
                resolveReveal(snapshot: viewportSnapshot, viewport: viewport.size, proxy: proxy)
            }
            .onChange(of: session.stripAssetIDs) { _, _ in
                requestReveal()
                resolveReveal(snapshot: viewportSnapshot, viewport: viewport.size, proxy: proxy)
            }
            .onChange(of: viewport.size) { _, size in
                requestReveal()
                resolveReveal(snapshot: viewportSnapshot, viewport: size, proxy: proxy)
            }
            .onDisappear { revealRequest = nil }
          }
        }
        .frame(height: ElasticLayout.filmstripHeight)
        .background(
            session.peek == .set
                ? LuminaTokens.Elastic.warmAccent.opacity(ElasticLayout.stripSetFillOpacity)
                : LuminaTokens.Elastic.shadowInk.opacity(ElasticLayout.filmstripFillOpacity)
        )
        #if DEBUG
        .workbenchHot()
        #endif
    }

    private func chronologyLabel(_ label: String) -> some View {
        Text(label)
            .font(ElasticType.mono(ElasticLayout.stripLabelSize))
            .foregroundStyle(LuminaTokens.Elastic.shellAlt.opacity(ElasticLayout.stripLabelOpacity))
            .fixedSize(horizontal: true, vertical: false)
    }

    private func requestReveal() {
        guard let id = session.focusedAssetID, session.stripAssetIDs.contains(id) else {
            revealRequest = nil
            return
        }
        revealRequest = ElasticViewportReveal.Request(
            id: id, expectedSize: ElasticLayout.filmstripFocusedTile
        )
    }

    private func resolveReveal(snapshot: ElasticViewportSnapshot, viewport: CGSize, proxy: ScrollViewProxy) {
        guard var request = revealRequest else { return }
        switch request.resolve(frames: snapshot.tiles, viewport: CGRect(origin: .zero, size: viewport), realizedContainers: snapshot.containers) {
        case .wait: break
        case .finished: revealRequest = nil
        case .reveal(let id, _):
            revealRequest = nil
            proxy.scrollTo(id)
        }
    }

    private func tile(_ asset: AssetRecord) -> some View {
        let focused = session.focusedAssetID == asset.id
        let ringed = focused || session.selectedAssetIDs.contains(asset.id)
        let inSet = session.isInFinalSet(asset.id)
        let size = focused ? ElasticLayout.filmstripFocusedTile : ElasticLayout.filmstripTile

        return ZStack {
            LuminaTokens.Elastic.deep
            if let path = asset.gridThumbPath ?? asset.thumbPath {
                ChapterPlateImage(path: path)
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(ElasticViewportTile(id: asset.id))
        .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.tileRadius, style: .continuous))
        .elasticMarked(radius: ElasticLayout.tileRadius, ringed: ringed, inSet: inSet)
        .opacity(asset.cull == .reject ? ElasticLayout.outOpacity : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(P0AccessibilityID.elasticTile(asset.id))
        .onTapGesture { session.setFocus(asset.id) }
    }
}
