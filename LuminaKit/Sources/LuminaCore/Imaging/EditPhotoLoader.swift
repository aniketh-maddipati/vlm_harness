import Foundation
import CoreGraphics
import Observation

// WP-4. Loading the Edit photo (R-42, R-44, R-81): a small picture at once, the sharp one when
// it is decoded, the neighbours after that. One load at a time; a newer photo cancels the older
// load, and while a look is being rendered only the newest waiting look is rendered next.

@MainActor @Observable
public final class EditPhotoLoader {
    /// The size of the small picture shown blurred while the sharp one decodes.
    public static let lowPixel = 180

    public struct Request: Equatable, Sendable {
        public var id: String
        public var look: Look?
        public var maxPixel: Int
    }

    /// The photo `low` and `sharp` belong to.
    public private(set) var photoID: String?
    public private(set) var low: CGImage?
    public private(set) var sharp: CGImage?
    /// Counts the photos whose first sharp picture arrived (the view fades that one in).
    public private(set) var sharpSerial = 0
    /// The file that couldn't be opened ("Couldn’t open {file}").
    public private(set) var failedFile: String?

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var current: Request?
    @ObservationIgnored private var pending: (Photo, Request)?
    @ObservationIgnored private var photo: Photo?
    @ObservationIgnored private var rendering = false
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    /// Show `photo` with `look` at `maxPixel`. Call it whenever any of the three changes.
    public func show(_ photo: Photo?, look: Look?, maxPixel: Int, in model: AppModel) {
        guard let photo else { clear(); return }
        let look = look.flatMap { $0.isEmpty ? nil : $0 }
        let req = Request(id: photo.id, look: look, maxPixel: maxPixel)
        if req == current, failedFile == nil { return }
        if photo.id != photoID || sharp == nil {
            begin(photo, req, in: model)
        } else {
            current = req; self.photo = photo
            if rendering { pending = (photo, req) } else { run(photo, req, first: false, in: model) }
        }
    }

    /// Retry after a failure (R-44).
    public func retry(in model: AppModel) {
        guard let p = photo, let r = current else { return }
        begin(p, r, in: model)
    }

    /// The sharp picture has faded in: the small one is no longer needed.
    public func dropLow(serial: Int) { if serial == sharpSerial, sharp != nil { low = nil } }

    public func clear() {
        generation += 1; task?.cancel(); task = nil
        photoID = nil; photo = nil; current = nil; pending = nil; low = nil; sharp = nil; failedFile = nil; rendering = false
    }

    /// Wait for the load in flight (tests).
    public func settle() async { while let t = task { await t.value; if t == task { break } } }

    private func begin(_ photo: Photo, _ req: Request, in model: AppModel) {
        generation += 1; task?.cancel()
        model.services.images.cancelPreloads()
        let keepLow = photoID == photo.id
        photoID = photo.id; self.photo = photo; current = req; pending = nil
        if !keepLow { low = nil }
        sharp = nil; failedFile = nil
        model.edit.photo = .loading; model.edit.loadingFullSize = true
        run(photo, req, first: true, in: model)
    }

    private func run(_ photo: Photo, _ req: Request, first: Bool, in model: AppModel) {
        let g = generation, images = model.services.images
        rendering = true
        task = Task { [weak self, weak model] in
            var failed = false
            do {
                if first, self?.low == nil {
                    let small = try await images.image(for: photo, maxPixel: Self.lowPixel, look: req.look)
                    guard let self, self.generation == g else { return }
                    self.low = small
                }
                let img = try await images.image(for: photo, maxPixel: req.maxPixel, look: req.look)
                guard let self, self.generation == g, let model else { return }
                self.sharp = img
                if first { self.sharpSerial += 1 }
                self.failedFile = nil
                model.edit.photo = .loaded; model.edit.loadingFullSize = false
                self.preloadNeighbours(of: photo, maxPixel: req.maxPixel, in: model)
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
            guard let self, self.generation == g else { return }
            // A look that failed to render keeps the picture already on screen; a photo that
            // never showed says so (R-44: never a blank frame).
            if failed, self.sharp == nil, let model {
                self.failedFile = photo.file
                model.edit.photo = .failed; model.edit.loadingFullSize = false
            }
            self.rendering = false
            if let (p, r) = self.pending, let model {
                self.pending = nil
                self.run(p, r, first: self.sharp == nil, in: model)
            }
        }
    }

    /// Once the photo is sharp: the next two and the previous one, at low priority (R-42).
    private func preloadNeighbours(of photo: Photo, maxPixel: Int, in model: AppModel) {
        guard model.step == .edit else { return }
        let kept = model.keptIDs
        guard let i = kept.firstIndex(of: photo.id) else { return }
        let near = [i + 1, i + 2, i - 1].filter { kept.indices.contains($0) }.compactMap { model.shoot.photo(kept[$0]) }
        if !near.isEmpty { model.services.images.preload(near, maxPixel: maxPixel) }
    }
}
