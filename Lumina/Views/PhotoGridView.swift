import SwiftUI
import AppKit

/// NSCollectionView-backed photo grid with cell reuse and prefetch.
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
        context.coordinator.photos = photos
        context.coordinator.selectedID = selectedID
        context.coordinator.onSelect = onSelect

        // Resize cells to fit column width (avoids clipped / tiny grid on wide windows)
        if let collection = context.coordinator.collectionView,
           let layout = context.coordinator.layout,
           nsView.contentSize.width > 100 {
            let inset: CGFloat = 20
            let spacing: CGFloat = 10
            let minCell: CGFloat = 180
            let available = nsView.contentSize.width - inset
            let cols = max(1, Int(floor((available + spacing) / (minCell + spacing))))
            let cellW = floor((available - spacing * CGFloat(cols - 1)) / CGFloat(cols))
            layout.itemSize = NSSize(width: cellW, height: cellW * 0.78 + 28)
            layout.invalidateLayout()
        }

        context.coordinator.collectionView?.reloadData()
        if let id = selectedID,
           let index = photos.firstIndex(where: { $0.id == id }) {
            let path = IndexPath(item: index, section: 0)
            context.coordinator.collectionView?.selectionIndexPaths = [path]
        }
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var photos: [PhotoRecord] = []
        var selectedID: UUID?
        var onSelect: (UUID) -> Void
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

    override func loadView() {
        view = NSView()
        imageView_.imageScaling = .scaleProportionallyUpOrDown
        imageView_.imageAlignment = .alignCenter
        imageView_.wantsLayer = true
        imageView_.layer?.cornerRadius = 6
        imageView_.layer?.masksToBounds = true

        badge.font = .systemFont(ofSize: 9, weight: .bold)
        badge.textColor = .white
        badge.drawsBackground = true
        badge.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.85)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4

        nameLabel.font = .systemFont(ofSize: 9)
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
        nameLabel.stringValue = photo.filename
        badge.stringValue = " \(photo.tier.label) "
        switch photo.tier {
        case .keep: badge.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.85)
        case .reject: badge.backgroundColor = NSColor.systemGray.withAlphaComponent(0.85)
        case .unranked:
            badge.backgroundColor = photo.isFlagged
                ? NSColor.systemOrange.withAlphaComponent(0.85)
                : NSColor.systemBlue.withAlphaComponent(0.7)
        }
        view.layer?.borderWidth = selected ? 2 : 0
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
        view.wantsLayer = true

        // Scale image area with cell width
        let cellW = view.bounds.width
        if cellW > 40 {
            imageHeight?.constant = max(80, cellW * 0.72)
        }

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
                    guard token == self.loadToken else { return }
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
}
