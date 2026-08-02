import SwiftUI

/// Browse keeps — carousel by default, morphs to full-screen loupe with filmstrip on focus.
struct KeepsBrowserView: View {
    @Bindable var model: ProjectViewModel

    private var keeps: [PhotoRecord] { model.displayedPhotos }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                browserChrome
                    .padding(.horizontal, 16)
                    .padding(.vertical, model.keepsBrowseLayout == .focus ? 6 : 10)

                Group {
                    switch model.keepsBrowseLayout {
                    case .carousel:
                        carouselLayout(height: geo.size.height - chromeHeight(focused: false))
                    case .focus:
                        focusLayout(height: geo.size.height - chromeHeight(focused: true))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.prepareKeepsBrowser() }
    }

    // MARK: - Carousel

    @ViewBuilder
    private func carouselLayout(height: CGFloat) -> some View {
        VStack(spacing: 16) {
            if keeps.isEmpty {
                ContentUnavailableView("No keeps yet", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FloatingPhotoCarousel(
                    items: keeps,
                    selection: $model.selectedPhotoID,
                    itemID: \.id,
                    spacing: 28,
                    peek: 5,
                    onSelectionChange: { model.prefetchPhotoDisplay($0) }
                ) { photo, centered in
                    FloatingPhotoCard(
                        photo: photo,
                        projectName: model.project?.name,
                        centered: centered
                    )
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: max(280, height * 0.72))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectPhoto(photo.id)
                    }
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            model.selectPhoto(photo.id)
                            model.focusKeep()
                        }
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: max(320, height * 0.78))

                if let photo = model.selectedPhoto {
                    VStack(spacing: 4) {
                        Text(photo.filename)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text("Double-click or Return to fill the screen · ← → to browse")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Focus (loupe)

    @ViewBuilder
    private func focusLayout(height: CGFloat) -> some View {
        let filmstripH: CGFloat = 92
        let previewH = max(240, height - filmstripH - 8)

        VStack(spacing: 8) {
            if let photo = model.selectedPhoto, let project = model.project {
                SoftPreviewView(
                    photo: photo,
                    projectName: project.name,
                    baseline: project.profile,
                    offsets: model.globalAdjustments.merged(with: photo.perPhotoAdjustments ?? .zero),
                    mix: model.showBefore ? 0 : model.softRender.mix,
                    showBefore: model.showBefore
                )
                .frame(maxWidth: .infinity, maxHeight: previewH)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

                filmstrip
                    .frame(height: filmstripH)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(keeps) { photo in
                        Button {
                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) {
                                model.selectPhoto(photo.id)
                            }
                        } label: {
                            PhotoImageView(photo: photo, tier: .preview, contentMode: .fill)
                                .frame(width: 72, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(
                                            model.selectedPhotoID == photo.id ? Color.accentColor : .clear,
                                            lineWidth: 2
                                        )
                                }
                        }
                        .buttonStyle(LuminaPressStyle(pressedScale: 0.95))
                        .id(photo.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: model.selectedPhotoID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Chrome

    private var browserChrome: some View {
        HStack(spacing: 12) {
            if model.keepsBrowseLayout == .focus {
                Button {
                    model.unfocusKeep()
                } label: {
                    Label("Carousel", systemImage: "rectangle.grid.1x2")
                }
                .buttonStyle(LuminaPressStyle())
            } else {
                Text("Keeps")
                    .font(.headline)
            }

            Spacer()

            if model.keepsBrowseLayout == .carousel {
                Picker("Sort", selection: $model.sortMode) {
                    Text("Similar").tag(SortMode.similar)
                    Text("Quality").tag(SortMode.quality)
                    Text("Sharpest").tag(SortMode.sharpest)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            } else if let photo = model.selectedPhoto {
                Text(photo.filename)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Back to session") {
                model.unfocusKeep()
                model.appSpine = .stackFeed
            }
            .buttonStyle(LuminaPressStyle())
        }
    }

    private func chromeHeight(focused: Bool) -> CGFloat {
        focused ? 44 : 52
    }
}
