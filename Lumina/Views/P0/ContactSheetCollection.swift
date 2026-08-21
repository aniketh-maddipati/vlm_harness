import AppKit
import QuartzCore

/// Tap target for D47 / A3 pointer cull marks — decides on mouseDown; no hover handlers (D48).
final class PointerCullMarkControl: NSView {
    var onPress: (() -> Void)?

    init(symbol: String, keyLetter: String, accessibilityID: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.11, alpha: 0.88).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor

        let symbolLabel = NSTextField(labelWithString: symbol)
        symbolLabel.font = .systemFont(ofSize: 16, weight: .bold)
        symbolLabel.textColor = NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1)
        symbolLabel.alignment = .center
        symbolLabel.translatesAutoresizingMaskIntoConstraints = false
        symbolLabel.setAccessibilityElement(false)

        let keyLabel = NSTextField(labelWithString: keyLetter)
        keyLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        keyLabel.textColor = NSColor(srgbRed: 0.82, green: 0.80, blue: 0.76, alpha: 1)
        keyLabel.alignment = .center
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyLabel.setAccessibilityElement(false)

        addSubview(symbolLabel)
        addSubview(keyLabel)

        let hit = HiFiTokens.Grammar.pointerCullMarkMinHit
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: hit),
            heightAnchor.constraint(equalToConstant: hit),
            symbolLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            keyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            keyLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier(accessibilityID)
        setAccessibilityLabel(accessibilityLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onPress?()
    }
}

/// Row-packing layout: fixed row height, cell width from aspect ratio — no uniform crop.
final class ContactSheetLayout: NSCollectionViewLayout {
    var rowHeight: CGFloat = 160
    var spacing: CGFloat = 10
    var sectionInset = NSEdgeInsets(top: 16, left: 28, bottom: 28, right: 28)
    var aspects: [CGFloat] = []

    private var attributes: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    private var contentHeight: CGFloat = 0
    private var contentWidth: CGFloat = 0

    override var collectionViewContentSize: NSSize {
        NSSize(width: contentWidth, height: contentHeight)
    }

    override func prepare() {
        attributes.removeAll(keepingCapacity: true)
        guard let collectionView else { return }
        contentWidth = collectionView.bounds.width
        guard contentWidth > 40, !aspects.isEmpty else {
            contentHeight = 0
            return
        }

        let usable = contentWidth - sectionInset.left - sectionInset.right
        var x = sectionInset.left
        var y = sectionInset.top
        var rowMaxHeight = rowHeight

        for (index, aspect) in aspects.enumerated() {
            let ratio = max(aspect, 0.35)
            let width = min(usable, rowHeight * ratio)
            if x > sectionInset.left, x + width > sectionInset.left + usable {
                x = sectionInset.left
                y += rowMaxHeight + spacing
            }
            let frame = NSRect(x: x, y: y, width: width, height: rowHeight)
            let path = IndexPath(item: index, section: 0)
            let attrs = NSCollectionViewLayoutAttributes(forItemWith: path)
            attrs.frame = frame
            attributes[path] = attrs
            x += width + spacing
        }
        contentHeight = y + rowMaxHeight + sectionInset.bottom
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        attributes.values.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        attributes[indexPath]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        abs(newBounds.width - contentWidth) > 0.5
    }
}

final class ContactSheetItemView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("P0ContactSheetItem")

    private let imageView_ = NSImageView()
    private let focusRing = NSView()
    private let markStack = NSStackView()
    private let pointerCullStack = NSStackView()
    private var pointerKeepControl: PointerCullMarkControl!
    private var pointerRejectControl: PointerCullMarkControl!
    private var loadToken = UUID()
    private var boundID: UUID?
    private var aspectConstraint: NSLayoutConstraint?

    override func loadView() {
        pointerKeepControl = PointerCullMarkControl(
            symbol: "✓",
            keyLetter: "P",
            accessibilityID: P0AccessibilityID.pointerCullKeep,
            accessibilityLabel: "Keep, P"
        )
        pointerRejectControl = PointerCullMarkControl(
            symbol: "✕",
            keyLetter: "X",
            accessibilityID: P0AccessibilityID.pointerCullReject,
            accessibilityLabel: "Reject, X"
        )
        view = NSView()
        view.wantsLayer = true

        imageView_.imageScaling = .scaleProportionallyUpOrDown
        imageView_.imageAlignment = .alignCenter
        imageView_.wantsLayer = true
        imageView_.layer?.cornerRadius = 3
        imageView_.layer?.masksToBounds = true
        imageView_.translatesAutoresizingMaskIntoConstraints = false
        // Only the cell container is an accessibility element — inner views must not duplicate its
        // identifier (a duplicate makes XCUITest's firstMatch ambiguous and clicks land wrong).
        imageView_.setAccessibilityElement(false)
        focusRing.setAccessibilityElement(false)
        markStack.setAccessibilityElement(false)

        focusRing.wantsLayer = true
        focusRing.layer?.borderWidth = 0
        focusRing.layer?.cornerRadius = 4
        focusRing.translatesAutoresizingMaskIntoConstraints = false

        markStack.orientation = .horizontal
        markStack.spacing = 3
        markStack.translatesAutoresizingMaskIntoConstraints = false

        pointerCullStack.orientation = .horizontal
        pointerCullStack.spacing = 6
        pointerCullStack.translatesAutoresizingMaskIntoConstraints = false
        pointerCullStack.addArrangedSubview(pointerKeepControl)
        pointerCullStack.addArrangedSubview(pointerRejectControl)
        pointerCullStack.setAccessibilityElement(false)
        pointerKeepControl.setAccessibilityElement(false)
        pointerRejectControl.setAccessibilityElement(false)

        view.addSubview(imageView_)
        view.addSubview(focusRing)
        view.addSubview(markStack)
        view.addSubview(pointerCullStack)

        NSLayoutConstraint.activate([
            imageView_.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            imageView_.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            imageView_.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
            imageView_.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),
            focusRing.topAnchor.constraint(equalTo: view.topAnchor),
            focusRing.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            focusRing.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            focusRing.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            markStack.topAnchor.constraint(equalTo: imageView_.topAnchor, constant: 6),
            markStack.leadingAnchor.constraint(equalTo: imageView_.leadingAnchor, constant: 6),
            pointerCullStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            pointerCullStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
    }

    func configure(
        item: ContactSheetItem,
        focused: Bool,
        selected: Bool,
        showPointerCullTargets: Bool,
        onPointerKeep: (() -> Void)?,
        onPointerReject: (() -> Void)?
    ) {
        let identityChanged = boundID != item.id
        boundID = item.id
        // Stable per-asset accessibility identity — keyed by durable asset UUID, never array index.
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityIdentifier(P0AccessibilityID.assetCell(item.id))
        view.setAccessibilityLabel(item.asset.filename)
        applyChrome(marks: item.marks, focused: focused, selected: selected)
        applyPointerCullChrome(
            visible: showPointerCullTargets,
            onKeep: onPointerKeep,
            onReject: onPointerReject
        )

        if identityChanged {
            imageView_.image = nil
            loadToken = UUID()
            loadImage(for: item.asset)
        } else if imageView_.image == nil {
            loadImage(for: item.asset)
        }
    }

    func applyChrome(marks: ContactSheetMarks, focused: Bool, selected: Bool) {
        // Focus: warm-charcoal outline. Selection: warm accent outline — distinct rings.
        let charcoal = NSColor(srgbRed: 0.22, green: 0.21, blue: 0.20, alpha: 0.95)
        let warmAccent = NSColor(srgbRed: 0.72, green: 0.48, blue: 0.22, alpha: 0.95)

        if focused {
            focusRing.layer?.borderWidth = 2.5
            focusRing.layer?.borderColor = charcoal.cgColor
        } else if selected {
            focusRing.layer?.borderWidth = 2.0
            focusRing.layer?.borderColor = warmAccent.cgColor
        } else {
            focusRing.layer?.borderWidth = 0
        }

        // Rejected: ~50% dimming; readable marks stay on top.
        imageView_.alphaValue = marks.rejected ? 0.50 : 1.0

        markStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if marks.kept {
            addMarkChip(symbol: "✓", fill: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.19, alpha: 0.82))
        }
        if marks.rejected {
            addMarkChip(symbol: "✕", fill: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.19, alpha: 0.82))
        }
        if marks.edited {
            // Small adjustment bar — distinct from Keep checkmark.
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor(srgbRed: 0.95, green: 0.93, blue: 0.88, alpha: 0.95).cgColor
            bar.layer?.cornerRadius = 1.5
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.widthAnchor.constraint(equalToConstant: 18).isActive = true
            bar.heightAnchor.constraint(equalToConstant: 3).isActive = true
            markStack.addArrangedSubview(bar)
        }
        if let order = marks.orderIndex {
            addMarkChip(symbol: "\(order)", fill: NSColor(srgbRed: 0.20, green: 0.20, blue: 0.19, alpha: 0.82))
        }
        // Unreviewed: no mark.

        // Structured per-cell state for the UI-test harness (never the sole source of truth,
        // but lets tests assert one cell's focus/selection/cull/edit without scraping pixels).
        view.setAccessibilityValue(Self.cellStateValue(marks: marks, focused: focused, selected: selected))
    }

    fileprivate func applyPointerCullChrome(
        visible: Bool,
        onKeep: (() -> Void)?,
        onReject: (() -> Void)?
    ) {
        pointerCullStack.isHidden = !visible
        pointerKeepControl.onPress = visible ? onKeep : nil
        pointerRejectControl.onPress = visible ? onReject : nil
        pointerKeepControl.setAccessibilityElement(visible)
        pointerRejectControl.setAccessibilityElement(visible)
    }

    /// Compact, parseable cell-state string, e.g. `cull:keep;focus:1;sel:0;edit:1`.
    static func cellStateValue(marks: ContactSheetMarks, focused: Bool, selected: Bool) -> String {
        let cull: String
        if marks.kept { cull = "keep" }
        else if marks.rejected { cull = "reject" }
        else { cull = "unreviewed" }
        return "cull:\(cull);focus:\(focused ? 1 : 0);sel:\(selected ? 1 : 0);edit:\(marks.edited ? 1 : 0)"
    }

    private func addMarkChip(symbol: String, fill: NSColor) {
        let label = NSTextField(labelWithString: " \(symbol) ")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1)
        label.drawsBackground = true
        label.backgroundColor = fill
        label.wantsLayer = true
        label.layer?.cornerRadius = 3
        // High-contrast chip remains readable on bright and dark photographs.
        label.layer?.borderWidth = 0.5
        label.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        markStack.addArrangedSubview(label)
    }

    private func loadImage(for asset: AssetRecord) {
        // Prefer the 1600px browse preview over the 768px grid cache — upscaled
        // grid JPEGs read as grainy/soft on Retina contact-sheet cells.
        guard let path = asset.thumbPath ?? asset.gridThumbPath else {
            imageView_.image = nil
            return
        }
        let hitStart = CFAbsoluteTimeGetCurrent()
        let token = UUID()
        loadToken = token
        let pixelSize = Int(max(view.bounds.width, 120) * (NSScreen.main?.backingScaleFactor ?? 2))
        Task {
            let outcome = await PhotoImageCache.shared.load(
                path: path,
                maxPixelSize: max(pixelSize, 180),
                allowRAW: false
            )
            await MainActor.run {
                guard token == self.loadToken, self.boundID == asset.id else { return }
                if case .image(let img) = outcome {
                    self.imageView_.image = img
                    LatencyMetrics.record(
                        "p0.visible_cell_cache",
                        milliseconds: (CFAbsoluteTimeGetCurrent() - hitStart) * 1000
                    )
                }
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken = UUID()
        boundID = nil
        imageView_.image = nil
    }
}

/// Collection view that owns double-click → open (zoom into photograph).
/// NSViewController.mouseDown never receives cell clicks; this must live on the view.
final class ContactSheetCollectionView: NSCollectionView {
    var onDoubleClickItem: ((IndexPath) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            if let indexPath = indexPathForItem(at: point) {
                onDoubleClickItem?(indexPath)
                return
            }
        }
        super.mouseDown(with: event)
    }
}

/// AppKit contact sheet with virtualization, incremental updates, and distinct focus/selection.
final class ContactSheetCollectionController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private let scrollView = NSScrollView()
    private let collectionView = ContactSheetCollectionView()
    private let layout = ContactSheetLayout()

    var items: [ContactSheetItem] = []
    var focusedID: UUID?
    var selectedIDs: Set<UUID> = []
    var densityColumns: Int = 6 {
        didSet { updateRowHeight(); layout.invalidateLayout() }
    }

    var onFocus: ((UUID) -> Void)?
    var onSelectClick: ((_ id: UUID, _ command: Bool, _ shift: Bool) -> Void)?
    var onOpen: ((UUID) -> Void)?
    var onDensityDelta: ((Int) -> Void)?
    var onScrollAnchor: ((Double) -> Void)?
    var onVisibleRange: ((Range<Int>) -> Void)?
    var pointerCullEnabled = true
    var onPointerMarkKeep: (() -> Void)?
    var onPointerMarkReject: (() -> Void)?

    private var itemIDs: [UUID] = []
    private var magnifyAccum: CGFloat = 0
    /// Grid becomes keyboard-ready on first load so arrows/P/X work without a prior click.
    private var didEstablishInitialFocus = false

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.scrollerStyle = .overlay

        layout.rowHeight = rowHeight(for: densityColumns)
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(ContactSheetItemView.self, forItemWithIdentifier: ContactSheetItemView.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.setAccessibilityIdentifier(P0AccessibilityID.contactCollection)
        collectionView.onDoubleClickItem = { [weak self] indexPath in
            guard let self, indexPath.item < self.items.count else { return }
            self.onOpen?(self.items[indexPath.item].id)
        }
        scrollView.documentView = collectionView
        view = scrollView

        let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        collectionView.addGestureRecognizer(magnify)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        P0RenderInstruments.shared.attach(to: scrollView)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        P0RenderInstruments.shared.detach()
    }

    func apply(
        items: [ContactSheetItem],
        focusedID: UUID?,
        selectedIDs: Set<UUID>,
        densityColumns: Int,
        restoreScrollAnchor: Double?,
        forceScrollRestore: Bool = false
    ) {
        let newIDs = items.map(\.id)
        let oldIDs = itemIDs
        let idsChanged = newIDs != oldIDs
        let oldCount = oldIDs.count
        self.items = items
        self.itemIDs = newIDs
        self.focusedID = focusedID
        self.selectedIDs = selectedIDs
        self.densityColumns = densityColumns
        layout.aspects = items.map(\.aspectRatio)
        updateRowHeight()

        if idsChanged {
            let prefixOK = isPrefixCompatible(old: oldIDs, new: newIDs)
            if oldCount == 0 || abs(newIDs.count - oldCount) > 40 || !prefixOK {
                let anchor = restoreScrollAnchor ?? currentScrollAnchor()
                collectionView.reloadData()
                DispatchQueue.main.async { [weak self] in
                    self?.restoreScroll(anchor: anchor)
                    self?.applyFocusSelectionChrome()
                }
            } else if newIDs.count > oldCount, Array(newIDs.prefix(oldCount)) == oldIDs {
                // Incremental insertion without full-grid reload.
                let paths = (oldCount..<newIDs.count).map { IndexPath(item: $0, section: 0) }
                collectionView.performBatchUpdates({
                    collectionView.insertItems(at: Set(paths))
                }, completionHandler: { [weak self] _ in
                    self?.applyFocusSelectionChrome()
                })
            } else {
                let anchor = restoreScrollAnchor ?? currentScrollAnchor()
                collectionView.reloadData()
                DispatchQueue.main.async { [weak self] in
                    self?.restoreScroll(anchor: anchor)
                    self?.applyFocusSelectionChrome()
                }
            }
        } else {
            // Cull / focus / selection — chrome only; never reloadData for one-cell decisions.
            applyFocusSelectionChrome()
            refreshVisibleCells()
            if forceScrollRestore, let anchor = restoreScrollAnchor {
                restoreScroll(anchor: anchor)
            }
        }

        establishInitialFocusIfNeeded()
    }

    /// Make the collection the window's first responder once, when assets first appear, so keyboard
    /// grammar (arrows, P/X, ⌘Z) is available immediately on open — no click required.
    private func establishInitialFocusIfNeeded() {
        guard !didEstablishInitialFocus, !items.isEmpty,
              let window = collectionView.window else { return }
        // Don't steal focus from an active text field (none on the P0 sheet, but be defensive).
        if !(window.firstResponder is NSText) {
            window.makeFirstResponder(collectionView)
        }
        didEstablishInitialFocus = true
    }

    // MARK: - Data source

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ContactSheetItemView.identifier, for: indexPath) as! ContactSheetItemView
        let model = items[indexPath.item]
        configureItemCell(item, model: model)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let path = indexPaths.first else { return }
        let id = items[path.item].id
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        onSelectClick?(id, flags.contains(.command), flags.contains(.shift))
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        reportVisibleRange()
    }

    // MARK: - Keyboard helpers (driven from SwiftUI host)

    func moveFocus(dx: Int, dy: Int) {
        // Host owns focus movement using density columns.
    }

    // MARK: - Internals

    private func updateRowHeight() {
        layout.rowHeight = rowHeight(for: densityColumns)
    }

    private func rowHeight(for columns: Int) -> CGFloat {
        let width = max(collectionView.bounds.width, 800)
        let usable = width - layout.sectionInset.left - layout.sectionInset.right
        let col = CGFloat(max(columns, 2))
        let cellW = (usable - layout.spacing * (col - 1)) / col
        return max(88, cellW / 1.45)
    }

    private func applyFocusSelectionChrome() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard indexPath.item < items.count,
                  let cell = collectionView.item(at: indexPath) as? ContactSheetItemView else { continue }
            let model = items[indexPath.item]
            let showPointer = pointerCullTargetsVisible(for: model.id)
            cell.applyChrome(
                marks: model.marks,
                focused: model.id == focusedID,
                selected: selectedIDs.contains(model.id)
            )
            cell.applyPointerCullChrome(
                visible: showPointer,
                onKeep: showPointer ? onPointerMarkKeep : nil,
                onReject: showPointer ? onPointerMarkReject : nil
            )
        }
        if let focusedID,
           let index = items.firstIndex(where: { $0.id == focusedID }) {
            let path = IndexPath(item: index, section: 0)
            collectionView.selectionIndexPaths = [path]
            collectionView.scrollToItems(at: [path], scrollPosition: [.nearestVerticalEdge])
        }
    }

    private func refreshVisibleCells() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard indexPath.item < items.count,
                  let cell = collectionView.item(at: indexPath) as? ContactSheetItemView else { continue }
            configureItemCell(cell, model: items[indexPath.item])
        }
    }

    private func pointerCullTargetsVisible(for itemID: UUID) -> Bool {
        pointerCullEnabled && itemID == focusedID
    }

    private func configureItemCell(_ cell: ContactSheetItemView, model: ContactSheetItem) {
        let showPointer = pointerCullTargetsVisible(for: model.id)
        cell.configure(
            item: model,
            focused: model.id == focusedID,
            selected: selectedIDs.contains(model.id),
            showPointerCullTargets: showPointer,
            onPointerKeep: showPointer ? onPointerMarkKeep : nil,
            onPointerReject: showPointer ? onPointerMarkReject : nil
        )
    }

    private func currentScrollAnchor() -> Double {
        let docH = max(collectionView.bounds.height, 1)
        let visible = scrollView.contentView.bounds
        let maxY = max(docH - visible.height, 1)
        return Double(min(max(visible.origin.y / maxY, 0), 1))
    }

    private func restoreScroll(anchor: Double) {
        let docH = max(collectionView.bounds.height, 1)
        let visibleH = scrollView.contentView.bounds.height
        let maxY = max(docH - visibleH, 0)
        let y = CGFloat(anchor) * maxY
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc private func scrollChanged() {
        // Instrumentation only: marks the sheet as scrolling so the display link knows
        // which of its ticks are glide frames. No-op unless instruments are enabled.
        P0RenderInstruments.shared.noteScrollActivity()
        onScrollAnchor?(currentScrollAnchor())
        reportVisibleRange()
    }

    private func reportVisibleRange() {
        let visible = collectionView.indexPathsForVisibleItems().map(\.item).sorted()
        guard let first = visible.first, let last = visible.last else { return }
        onVisibleRange?(first..<(last + 1))
    }

    @objc private func handleMagnify(_ gr: NSMagnificationGestureRecognizer) {
        magnifyAccum += gr.magnification
        if magnifyAccum > 0.25 {
            onDensityDelta?(-1)
            magnifyAccum = 0
            armZoom(gr)
        } else if magnifyAccum < -0.25 {
            onDensityDelta?(1)
            magnifyAccum = 0
            armZoom(gr)
        }
        if gr.state == .ended || gr.state == .cancelled {
            magnifyAccum = 0
        }
        gr.magnification = 0
    }

    /// Stamp the pinch that just changed density, after the change has been dispatched.
    /// The recogniser's event time is the gesture's, not this callback's.
    private func armZoom(_ gr: NSMagnificationGestureRecognizer) {
        let stamp = NSApp.currentEvent?.timestamp ?? CACurrentMediaTime()
        P0RenderInstruments.shared.arm(P0RenderInstruments.Key.zoomGesture, at: stamp)
    }

    private func isPrefixCompatible(old: [UUID], new: [UUID]) -> Bool {
        let n = min(old.count, new.count)
        guard n > 0 else { return true }
        return Array(old.prefix(n)) == Array(new.prefix(n))
    }
}
