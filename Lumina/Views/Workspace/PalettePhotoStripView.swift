import AppKit
import SwiftUI

/// Horizontally scrolling, reuse-backed photograph strip for one palette row.
struct PalettePhotoStripView: NSViewRepresentable {
    let assets: [AssetPresentation]
    let selectedID: AssetID?
    let rowHeight: CGFloat
    let onSelect: (AssetID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let collection = NSCollectionView()
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.backgroundColors = [.clear]
        collection.register(PaletteStripItem.self, forItemWithIdentifier: PaletteStripItem.identifier)
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        scroll.documentView = collection
        context.coordinator.collectionView = collection
        context.coordinator.layout = layout
        context.coordinator.rowHeight = rowHeight
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.rowHeight = rowHeight

        let ids = assets.map(\.id)
        let dataChanged = coordinator.assetIDs != ids
        let selectionChanged = coordinator.selectedID != selectedID

        coordinator.assets = assets
        coordinator.assetIDs = ids
        coordinator.selectedID = selectedID

        if let layout = coordinator.layout {
            layout.itemSize = NSSize(width: rowHeight * 1.45, height: rowHeight)
            layout.invalidateLayout()
        }

        if dataChanged {
            coordinator.collectionView?.reloadData()
        } else if selectionChanged {
            coordinator.applySelectionOnly()
            coordinator.refreshVisibleItems()
        }
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var assets: [AssetPresentation] = []
        var assetIDs: [AssetID] = []
        var selectedID: AssetID?
        var rowHeight: CGFloat = 148
        var onSelect: (AssetID) -> Void
        weak var collectionView: NSCollectionView?
        weak var layout: NSCollectionViewFlowLayout?

        init(onSelect: @escaping (AssetID) -> Void) {
            self.onSelect = onSelect
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            assets.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: PaletteStripItem.identifier, for: indexPath) as! PaletteStripItem
            let asset = assets[indexPath.item]
            item.configure(asset: asset, selected: asset.id == selectedID, rowHeight: rowHeight)
            return item
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let path = indexPaths.first else { return }
            onSelect(assets[path.item].id)
        }

        func applySelectionOnly() {
            guard let collectionView else { return }
            if let id = selectedID, let index = assets.firstIndex(where: { $0.id == id }) {
                collectionView.selectionIndexPaths = [IndexPath(item: index, section: 0)]
            } else {
                collectionView.selectionIndexPaths = []
            }
        }

        func refreshVisibleItems() {
            guard let collectionView else { return }
            for indexPath in collectionView.indexPathsForVisibleItems() {
                guard indexPath.item < assets.count,
                      let item = collectionView.item(at: indexPath) as? PaletteStripItem else { continue }
                let asset = assets[indexPath.item]
                item.configure(asset: asset, selected: asset.id == selectedID, rowHeight: rowHeight)
            }
        }
    }
}

final class PaletteStripItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PaletteStripItem")

    private let hostingContainer = NSView()
    private var hostingView: NSHostingView<AnyView>?
    private var boundID: AssetID?

    override func loadView() {
        view = hostingContainer
        hostingContainer.translatesAutoresizingMaskIntoConstraints = false
    }

    func configure(asset: AssetPresentation, selected: Bool, rowHeight: CGFloat) {
        boundID = asset.id
        let width = max(rowHeight * asset.aspectRatio, rowHeight * 0.55)
        let root = AnyView(
            StablePhotoView(
                asset: asset,
                contentMode: .fit,
                cornerRadius: LuminaTokens.Radius.photographThumb,
                showDecisionBadge: true,
                isSelected: selected,
                maxPixelSize: 960
            )
            .frame(width: width, height: rowHeight)
        )
        if hostingView == nil {
            let host = NSHostingView(rootView: root)
            host.translatesAutoresizingMaskIntoConstraints = false
            hostingContainer.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: hostingContainer.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: hostingContainer.trailingAnchor),
                host.topAnchor.constraint(equalTo: hostingContainer.topAnchor),
                host.bottomAnchor.constraint(equalTo: hostingContainer.bottomAnchor),
            ])
            hostingView = host
        } else {
            hostingView?.rootView = root
        }
    }
}
