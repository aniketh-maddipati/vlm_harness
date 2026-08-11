// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
import SwiftUI
import AppKit

/// NSCollectionView-backed photo grid with cell reuse and prefetch.
/// Selection updates do not reload the complete grid.
struct PhotoGridView: NSViewRepresentable {
    let photos: [PhotoRecord]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 200, height: 168)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        let collection = NSCollectionView()
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.backgroundColors = [.clear]
        collection.register(PhotoItemView.self, forItemWithIdentifier: PhotoItemView.identifier)
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        scroll.documentView = collection
        context.coordinator.collectionView = collection
        context.coordinator.layout = layout
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect

        let photoIDs = photos.map(\.id)
        let dataChanged = coordinator.photoIDs != photoIDs
        let selectionChanged = coordinator.selectedID != selectedID

        if let collection = coordinator.collectionView,
           let layout = coordinator.layout,
           nsView.contentSize.width > 100 {
            let width = nsView.contentSize.width
            if abs(width - coordinator.lastContainerWidth) > 0.5 {
                coordinator.lastContainerWidth = width
                let inset: CGFloat = 20
                let spacing: CGFloat = 10
                let minCell: CGFloat = 180
                let available = width - inset
                let cols = max(1, Int(floor((available + spacing) / (minCell + spacing))))
                let cellW = floor((available - spacing * CGFloat(cols - 1)) / CGFloat(cols))
                let newSize = NSSize(width: cellW, height: cellW * 0.78 + 28)
                if layout.itemSize != newSize {
                    layout.itemSize = newSize
                    layout.invalidateLayout()
                }
            }
        }

        coordinator.photos = photos
        coordinator.photoIDs = photoIDs
        coordinator.selectedID = selectedID

        if dataChanged {
            let savedOffset = nsView.contentView.bounds.origin
            coordinator.collectionView?.reloadData()
            DispatchQueue.main.async {
                nsView.contentView.scroll(to: savedOffset)
                nsView.reflectScrolledClipView(nsView.contentView)
            }
        } else if selectionChanged {
            // Selection / badge only — never reloadData.
            coordinator.applySelectionOnly()
            coordinator.refreshVisibleBadges()
        }
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var photos: [PhotoRecord] = []
        var photoIDs: [UUID] = []
        var selectedID: UUID?
        var onSelect: (UUID) -> Void
        var lastContainerWidth: CGFloat = 0
        weak var collectionView: NSCollectionView?
        weak var layout: NSCollectionViewFlowLayout?

        init(onSelect: @escaping (UUID) -> Void) {
            self.onSelect = onSelect
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            photos.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: PhotoItemView.identifier, for: indexPath) as! PhotoItemView
            let photo = photos[indexPath.item]
            item.configure(photo: photo, selected: photo.id == selectedID)
            return item
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let path = indexPaths.first else { return }
            onSelect(photos[path.item].id)
            prefetchAround(path.item)
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            willDisplay item: NSCollectionViewItem,
            forRepresentedObjectAt indexPath: IndexPath
        ) {
            prefetchAround(indexPath.item)
        }

        func applySelectionOnly() {
            guard let collectionView else { return }
            if let id = selectedID,
               let index = photos.firstIndex(where: { $0.id == id }) {
                collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
            } else {
                collectionView.selectionIndexPaths = []
            }
        }

        func refreshVisibleBadges() {
            guard let collectionView else { return }
            for indexPath in collectionView.indexPathsForVisibleItems() {
                guard indexPath.item < photos.count,
                      let item = collectionView.item(at: indexPath) as? PhotoItemView else { continue }
                let photo = photos[indexPath.item]
                item.applyState(photo: photo, selected: photo.id == selectedID)
            }
        }

        private func prefetchAround(_ index: Int) {
            guard !photos.isEmpty else { return }
            let lo = max(0, index - 12)
            let hi = min(photos.count - 1, index + 24)
            for i in lo...hi {
                guard let path = photos[i].displayThumbPath else { continue }
                ThumbCache.shared.prefetch(path)
            }
        }
    }
}

final class PhotoItemView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PhotoItemView")

    private let imageView_ = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private var imageHeight: NSLayoutConstraint?
    private var loadToken = UUID()
    private var boundPhotoID: UUID?

    override func loadView() {
        view = NSView()
        imageView_.imageScaling = .scaleProportionallyUpOrDown
        imageView_.imageAlignment = .alignCenter
        imageView_.wantsLayer = true
        imageView_.layer?.cornerRadius = 12
        imageView_.layer?.masksToBounds = true

        badge.font = .systemFont(ofSize: 10, weight: .medium)
        badge.textColor = .white
        badge.drawsBackground = true
        badge.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.85)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4

        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.textColor = .secondaryLabelColor

        imageView_.translatesAutoresizingMaskIntoConstraints = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView_)
        view.addSubview(badge)
        view.addSubview(nameLabel)

        let h = imageView_.heightAnchor.constraint(equalToConstant: 120)
        imageHeight = h
        NSLayoutConstraint.activate([
            imageView_.topAnchor.constraint(equalTo: view.topAnchor),
            imageView_.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView_.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            h,
            badge.topAnchor.constraint(equalTo: imageView_.topAnchor, constant: 4),
            badge.leadingAnchor.constraint(equalTo: imageView_.leadingAnchor, constant: 4),
            nameLabel.topAnchor.constraint(equalTo: imageView_.bottomAnchor, constant: 2),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])
    }

    func configure(photo: PhotoRecord, selected: Bool) {
        let identityChanged = boundPhotoID != photo.id
        boundPhotoID = photo.id
        nameLabel.stringValue = photo.filename
        applyState(photo: photo, selected: selected)

        let cellW = view.bounds.width
        if cellW > 40 {
            imageHeight?.constant = max(80, cellW * 0.72)
        }

        if identityChanged {
            imageView_.image = nil
            loadToken = UUID()
            loadImage(for: photo)
        } else if imageView_.image == nil {
            loadImage(for: photo)
        }
    }

    func applyState(photo: PhotoRecord, selected: Bool) {
        badge.stringValue = " \(photo.tier.label) "
        switch photo.tier {
        case .keep: badge.backgroundColor = NSColor(red: 0.61, green: 0.76, blue: 0.33, alpha: 0.92)
        case .reject: badge.backgroundColor = NSColor(red: 0.68, green: 0.13, blue: 0.07, alpha: 0.92)
        case .unranked:
            badge.backgroundColor = photo.isFlagged
                ? NSColor(red: 0.71, green: 0.46, blue: 0.08, alpha: 0.92)
                : NSColor(red: 0.05, green: 0.62, blue: 0.89, alpha: 0.75)
        }
        view.wantsLayer = true
        view.layer?.borderWidth = selected ? 1.5 : 0
        view.layer?.borderColor = NSColor(red: 0.05, green: 0.62, blue: 0.89, alpha: 0.85).cgColor
        view.layer?.cornerRadius = 4
    }

    private func loadImage(for photo: PhotoRecord) {
        if let path = photo.previewPath ?? photo.displayThumbPath {
            let token = UUID()
            loadToken = token
            let pixelSize = Int(max(view.bounds.width, 180) * (NSScreen.main?.backingScaleFactor ?? 2))
            Task {
                let outcome = await PhotoImageCache.shared.load(
                    path: path,
                    maxPixelSize: max(pixelSize, 256),
                    allowRAW: false
                )
                await MainActor.run {
                    guard token == self.loadToken, self.boundPhotoID == photo.id else { return }
                    if case .image(let img) = outcome {
                        self.imageView_.image = img
                    }
                }
            }
        } else {
            loadToken = UUID()
            imageView_.image = nil
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken = UUID()
        boundPhotoID = nil
        imageView_.image = nil
    }
}
