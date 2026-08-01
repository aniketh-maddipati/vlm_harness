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
        scroll.drawsBackground = false

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 220, height: 180)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

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
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.photos = photos
        context.coordinator.selectedID = selectedID
        context.coordinator.onSelect = onSelect
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
            let range = max(0, index - 12)...min(photos.count - 1, index + 24)
            for i in range {
                guard let path = photos[i].displayThumbPath else { continue }
                ThumbCache.shared.prefetch(path)
            }
        }
    }
}

final class ThumbCache {
    static let shared = ThumbCache()
    private let queue = DispatchQueue(label: "lumina.thumb-prefetch", qos: .utility, attributes: .concurrent)
    private var warm = Set<String>()
    private let lock = NSLock()

    private init() {}

    func prefetch(_ path: String) {
        lock.lock()
        let fresh = warm.insert(path).inserted
        lock.unlock()
        guard fresh else { return }
        queue.async {
            _ = NSImage(contentsOf: URL(fileURLWithPath: path))
        }
    }
}

final class PhotoItemView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PhotoItemView")

    private let imageView_ = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        imageView_.imageScaling = .scaleProportionallyUpOrDown
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

        NSLayoutConstraint.activate([
            imageView_.topAnchor.constraint(equalTo: view.topAnchor),
            imageView_.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView_.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView_.heightAnchor.constraint(equalToConstant: 140),
            badge.topAnchor.constraint(equalTo: imageView_.topAnchor, constant: 4),
            badge.leadingAnchor.constraint(equalTo: imageView_.leadingAnchor, constant: 4),
            nameLabel.topAnchor.constraint(equalTo: imageView_.bottomAnchor, constant: 2),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func configure(photo: PhotoRecord, selected: Bool) {
        nameLabel.stringValue = photo.filename
        badge.stringValue = " \(photo.tier.label) "
        switch photo.tier {
        case .keep: badge.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.85)
        case .maybe: badge.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.85)
        case .reject: badge.backgroundColor = NSColor.systemGray.withAlphaComponent(0.85)
        case .unranked: badge.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.7)
        }
        view.layer?.borderWidth = selected ? 2 : 0
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
        view.wantsLayer = true

        if let path = photo.displayThumbPath {
            DispatchQueue.global(qos: .userInitiated).async {
                let image = NSImage(contentsOf: URL(fileURLWithPath: path))
                DispatchQueue.main.async { self.imageView_.image = image }
            }
        } else {
            imageView_.image = nil
        }
    }
}
