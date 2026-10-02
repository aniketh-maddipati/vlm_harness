import SwiftUI
import LuminaCore

// WP-4. The Edit canvas (README §3 "Photo column"; R-41…R-46, R-55, R-81): the photo at its true
// aspect ratio, a small blurred picture at once and the sharp one faded in over 150 ms, zoom and
// pan, the zoom picker, the "Loading full size" chip, and the empty and failed states. Crop draws
// on top of it (`CropStage`). Every rule is a model function (`AppModel+Canvas.swift`); this file
// only measures, draws and forwards the pointer.

public struct EditCanvas: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.displayScale) private var displayScale
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                LuminaColor.bgCanvas
                if let p = model.shoot.photo(model.editCur) {
                    if model.edit.photo == .failed {
                        EditLoadError(file: model.photoLoader.failedFile ?? p.file)
                    } else {
                        EditPhotoStage(photo: p, canvas: size)
                    }
                } else {
                    EditEmptyState()
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.photo, style: .continuous))
            .onAppear { measured(geo) }
            .onChange(of: geo.size) { measured(geo) }
            .onChange(of: geo.frame(in: .global)) { _, f in Metrics.shared.canvas = f }
            .onChange(of: displayScale) { measured(geo) }
            .onChange(of: loadKey(size), initial: true) { _, key in load(key) }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier(AccessibilityID.Edit.canvas)
        .onDisappear { Metrics.shared.canvas = nil; Metrics.shared.photo = nil }
    }

    private func measured(_ geo: GeometryProxy) {
        Metrics.shared.canvas = geo.frame(in: .global)
        model.canvasResized(geo.size, backingScale: displayScale)
    }

    // MARK: loading

    /// What the canvas asks the loader for: the photo, the look it shows, the size to decode at.
    struct LoadKey: Equatable { var id: String?; var look: Look?; var px: Int }

    private func loadKey(_ size: CGSize) -> LoadKey {
        guard model.step == .edit, let id = model.editCur else { return LoadKey(id: nil, look: nil, px: 0) }
        // Zoomed in, the picture is decoded larger (up to the provider's 3600 px cap).
        let z = CGFloat(max(1, model.edit.overlay == .crop ? 1 : model.edit.zoom))
        let px = EditLayout.requestPixel(canvas: CGSize(width: size.width * z, height: size.height * z), backingScale: displayScale)
        return LoadKey(id: id, look: model.canvasLook, px: px)
    }

    private func load(_ key: LoadKey) {
        let loader = model.photoLoader
        guard let id = key.id, let p = model.shoot.photo(id) else { loader.clear(); return }
        loader.show(p, look: key.look, maxPixel: key.px, in: model)
    }
}

extension AppModel {
    /// The look the canvas draws. Before shows the photo as shot but keeps its crop, so the frame
    /// doesn't jump; while cropping, the whole turned and straightened frame shows under the box.
    var canvasLook: Look {
        if edit.overlay == .crop, let d = edit.cropDraft {
            let b = CropBox(d)
            var l = edit.before ? Look() : currentLook.withoutCrop
            if b.turns != 0 { l[CropKey.turns] = Double(b.turns) }
            if abs(b.angle) >= 0.05 { l[CropKey.angle] = b.angle }
            return l
        }
        return edit.before ? currentLook.cropOnly : currentLook
    }

    /// The aspect ratio of what the canvas draws (always the picture's own: R-41).
    func canvasAspect(_ p: Photo) -> Double {
        if edit.overlay == .crop, let d = edit.cropDraft { return CropBox(d).frameAspect(p.aspect) }
        return CropBox(currentLook).aspect(p.aspect)
    }
}

// MARK: the photo

/// The photo, zoomed and panned, with its pointer handling and the chips over the canvas.
struct EditPhotoStage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    @Environment(\.accessibilityReduceMotion) private var reduce
    let photo: Photo
    let canvas: CGSize
    @State private var dragLast: CGSize?
    @State private var pinchStart: Double?

    var body: some View {
        let cropping = model.edit.overlay == .crop
        let fit = EditLayout.photoRect(aspect: model.canvasAspect(photo), canvas: canvas, padding: EditLayout.padding(canvas: canvas))
        let r = cropping ? fit : EditLayout.zoomedRect(fit: fit, zoom: model.edit.zoom, pan: model.edit.pan)
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .gesture(panGesture)
                .simultaneousGesture(pinchGesture)
                .simultaneousGesture(tapGesture(r))
            EditPicture(photo: photo)
                .frame(width: max(1, r.width), height: max(1, r.height))
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)
            if cropping { CropStage(frame: fit) }
            chips(cropping: cropping)
        }
        .frame(width: canvas.width, height: canvas.height)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let p): model.canvas.pointer = CGPoint(x: p.x - canvas.width / 2, y: p.y - canvas.height / 2)
            case .ended: model.canvas.pointer = nil
            }
        }
    }

    @ViewBuilder private func chips(cropping: Bool) -> some View {
        if model.edit.before && !cropping {
            CanvasChip(text: "Before", bold: true)
                .padding(12.scaled(s)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
        }
        if !cropping {
            VStack(alignment: .trailing, spacing: 6.scaled(s)) {
                if model.edit.loadingFullSize && model.edit.photo == .loading { LoadingChip() }
                if canvas.width >= 300 { ZoomPicker() }
            }
            .padding(10.scaled(s)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    /// Dragging a zoomed photo looks around it.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { v in
                guard model.edit.overlay != .crop else { return }
                let last = dragLast ?? .zero
                model.panBy(CGSize(width: v.translation.width - last.width, height: v.translation.height - last.height))
                dragLast = v.translation
            }
            .onEnded { _ in dragLast = nil }
    }

    /// A pinch zooms about where it started.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                guard model.edit.overlay != .crop else { return }
                let z0 = pinchStart ?? model.edit.zoom
                if pinchStart == nil { pinchStart = z0 }
                let anchor = CGPoint(x: v.startLocation.x - canvas.width / 2, y: v.startLocation.y - canvas.height / 2)
                model.zoom(to: z0 * Double(v.magnification), anchor: anchor)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// A click: the white picker takes it when it is on; otherwise 1:1 at the click, again fits.
    private func tapGesture(_ r: CGRect) -> some Gesture {
        SpatialTapGesture()
            .onEnded { v in
                guard model.edit.overlay != .crop else { return }
                if model.edit.pickingWhite {
                    guard r.contains(v.location), r.width > 0, r.height > 0 else { return }
                    model.pickWhite(at: CGPoint(x: (v.location.x - r.minX) / r.width, y: (v.location.y - r.minY) / r.height))
                    return
                }
                model.zoomToggle(at: CGPoint(x: v.location.x - canvas.width / 2, y: v.location.y - canvas.height / 2))
            }
    }
}

/// The pictures: the small one blurred under, the sharp one faded in over it (R-42). Scaled to
/// fit, never stretched (R-41): for the moment a new crop is rendering, the old picture shows in
/// its own shape rather than squashed.
struct EditPicture: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    let photo: Photo

    var body: some View {
        let loader = model.photoLoader, mine = loader.photoID == photo.id
        ZStack {
            if mine, let low = loader.low {
                Image(decorative: low, scale: 1).resizable().interpolation(.medium).scaledToFit()
                    .blur(radius: LuminaSpacing.lowResBlur, opaque: true)
            }
            if mine, let sharp = loader.sharp {
                Image(decorative: sharp, scale: 1).resizable().interpolation(.high).scaledToFit()
                    .transition(.opacity)
            }
        }
        .animation(LuminaMotion.sharpFadeIn(reduce), value: loader.sharpSerial)
        .clipped()
        .luminaStatus(AccessibilityID.Edit.photo, model.edit.photo.rawValue)
        .background(GeometryReader { g in
            Color.clear.onChange(of: g.frame(in: .global), initial: true) { _, f in Metrics.shared.photo = f }
        })
        // Once the sharp picture has faded in, the small one goes.
        .task(id: loader.sharpSerial) {
            let serial = loader.sharpSerial
            try? await Task.sleep(nanoseconds: 220_000_000)
            loader.dropLow(serial: serial)
        }
    }
}

// MARK: chips

/// A dark rounded chip over the photo.
struct CanvasChip: View {
    @Environment(\.luminaScale) private var s
    let text: String
    var bold = false
    var body: some View {
        Text(text).font(LuminaFont.small(s, bold ? .bold : .regular)).foregroundStyle(LuminaColor.textPrimary)
            .padding(.horizontal, 10.scaled(s)).frame(height: 24.scaled(s))
            .background(Capsule().fill(LuminaColor.overlayScrim))
    }
}

/// "Loading full size", with a small spinner (the only thing that loops: R-61).
struct LoadingChip: View {
    @Environment(\.luminaScale) private var s
    var body: some View {
        HStack(spacing: 6.scaled(s)) {
            ProgressView().controlSize(.mini).progressViewStyle(.circular)
            Text("Loading full size").font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textSecondary)
        }
        .padding(.horizontal, 9.scaled(s)).frame(height: 22.scaled(s))
        .background(Capsule().fill(LuminaColor.overlayChip))
        .allowsHitTesting(false)
    }
}

/// Small / Fit / {percent} / 1:1 / 2:1 (R-46). `edit.zoom`, value = the zoom factor.
struct ZoomPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    var body: some View {
        let z = model.edit.zoom, levels = EditLayout.zoomLevels(oneToOne: model.edit.oneToOne, zoom: z)
        let onPreset = levels.contains { $0.id != "percent" && abs($0.zoom - z) < 0.02 }
        HStack(spacing: 2.scaled(s)) {
            ForEach(levels, id: \.id) { level in
                let on = level.id == "percent" ? !onPreset || abs(level.zoom - z) < 0.02 : abs(level.zoom - z) < 0.02
                Button { model.setZoom(level.zoom) } label: {
                    Text(level.label).font(LuminaFont.small(s, on ? .semibold : .regular)).monospacedDigit()
                        .foregroundStyle(on ? LuminaColor.textPrimary : LuminaColor.textSecondary)
                        .padding(.horizontal, 8.scaled(s)).frame(height: 22.scaled(s))
                        .background(RoundedRectangle(cornerRadius: LuminaRadius.tabThumb.scaled(s), style: .continuous).fill(on ? LuminaColor.fill16 : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(level.label)
            }
        }
        .padding(2.scaled(s))
        .background(RoundedRectangle(cornerRadius: LuminaRadius.pill.scaled(s), style: .continuous).fill(LuminaColor.overlayScrim))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Edit.zoom)
        .accessibilityValue(String(format: "%.2f", z))
    }
}

// MARK: empty and failed

/// No keepers (R-45).
struct EditEmptyState: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    var body: some View {
        VStack(spacing: 10.scaled(s)) {
            Text("Nothing to edit yet").font(LuminaFont.ui(LuminaFontSize.title2, .semibold, s)).foregroundStyle(LuminaColor.textPrimary)
            Text("Edit works on the photos you keep. Press R on a photo in Cull to keep it, then come back.")
                .font(LuminaFont.body(s)).foregroundStyle(LuminaColor.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 340.scaled(s))
            Button { model.go(.cull) } label: { HStack(spacing: 10.scaled(s)) { Text("Go to Cull"); KeyHint("⌘2") } }
                .buttonStyle(.luminaPrimary)
                .accessibilityIdentifier(AccessibilityID.Edit.emptyGoCull)
                .padding(.top, 6.scaled(s))
        }
        .padding(20.scaled(s))
        .accessibilityElement(children: .contain).accessibilityIdentifier(AccessibilityID.Edit.empty)
    }
}

/// A photo that couldn't be opened: never a blank frame (R-44).
struct EditLoadError: View {
    @Environment(AppModel.self) private var model
    @Environment(\.luminaScale) private var s
    let file: String
    var body: some View {
        let title = "Couldn’t open \(file)"
        VStack(spacing: 10.scaled(s)) {
            Text(title).font(LuminaFont.ui(LuminaFontSize.button, .bold, s)).foregroundStyle(LuminaColor.textPrimary)
                .multilineTextAlignment(.center)
                .luminaStatus(AccessibilityID.Edit.loadError, title)
            Text("The file may be missing, still copying, or damaged. Your edits are safe.")
                .font(LuminaFont.small(s)).foregroundStyle(LuminaColor.textTertiary)
                .multilineTextAlignment(.center).frame(maxWidth: 320.scaled(s))
            Button("Retry") { model.photoLoader.retry(in: model) }
                .buttonStyle(.luminaSecondary)
                .accessibilityIdentifier(AccessibilityID.Edit.retry)
        }
        .padding(20.scaled(s))
    }
}
