import AppKit
import Metal
import QuartzCore
import SwiftUI

/// CAMetalLayer-backed browse canvas — aspect-fit only, event-driven draws (no idle redraw loop).
final class MetalBrowseNSView: NSView {
    private let metalLayer = CAMetalLayer()
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var vertexBuffer: MTLBuffer?

    private var currentTexture: MTLTexture?
    private var imagePixelSize = CGSize(width: 3, height: 2)
    private var boundPhotoID: UUID?
    private var boundGeneration: UInt64 = 0
    private var pendingPhotonTime: CFAbsoluteTime?
    private var needsRedraw = false
    private var matteRed: Double = 246 / 255
    private var matteGreen: Double = 246 / 255
    private var matteBlue: Double = 244 / 255

    private let metalAvailable: Bool
    var onPhotonPresent: ((CFAbsoluteTime) -> Void)?

    override init(frame frameRect: NSRect) {
        let device = MetalPreviewPool.shared.device ?? LuminaMetalDevice.shared
        self.device = device
        self.queue = device?.makeCommandQueue()
        self.metalAvailable = device != nil && queue != nil
        super.init(frame: frameRect)
        wantsLayer = true
        guard metalAvailable, let device else {
            layer = CALayer()
            layer?.backgroundColor = NSColor(calibratedRed: matteRed, green: matteGreen, blue: matteBlue, alpha: 1).cgColor
            return
        }
        layer = metalLayer
        metalLayer.device = device
        metalLayer.pixelFormat = ImagePixelFormat.metalPixelFormat
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        metalLayer.isOpaque = true
        metalLayer.displaySyncEnabled = false
        metalLayer.presentsWithTransaction = false
        buildPipeline()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textureReady(_:)),
            name: .luminaTextureReady,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        guard metalAvailable else { return }
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(
            width: max(bounds.width * metalLayer.contentsScale, 1),
            height: max(bounds.height * metalLayer.contentsScale, 1)
        )
        rebuildVertices()
        requestDraw()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMatteFromAppearance()
        requestDraw()
    }

    func bind(
        photoID: UUID?,
        jpegPath: String?,
        imageSize: CGSize?,
        generation: UInt64,
        photonInputTime: CFAbsoluteTime?,
        matteIsDark: Bool
    ) {
        updateMatte(dark: matteIsDark)
        boundPhotoID = photoID
        boundGeneration = generation
        pendingPhotonTime = photonInputTime

        if let imageSize, imageSize.width > 0, imageSize.height > 0 {
            imagePixelSize = imageSize
        }

        guard let photoID else {
            currentTexture = nil
            rebuildVertices()
            requestDraw()
            return
        }

        if let info = MetalPreviewPool.shared.textureInfo(for: photoID),
           generation == 0 || info.generation == generation || info.generation == boundGeneration {
            applyTexture(info, for: photoID)
            return
        }

        if let tex = MetalPreviewPool.shared.texture(for: photoID) {
            currentTexture = tex
            rebuildVertices()
            requestDraw()
            return
        }

        currentTexture = nil
        rebuildVertices()
        requestDraw()
        if let jpegPath {
            MetalPreviewPool.shared.scheduleUpload(
                id: photoID,
                jpegPath: jpegPath,
                distanceBias: 0,
                generation: generation
            )
        }
    }

    @objc private func textureReady(_ note: Notification) {
        guard let id = note.userInfo?["photoID"] as? UUID,
              id == boundPhotoID else { return }

        let generation = note.userInfo?["generation"] as? UInt64 ?? 0
        guard generation == 0 || generation == boundGeneration else { return }

        if let w = note.userInfo?["pixelWidth"] as? Int,
           let h = note.userInfo?["pixelHeight"] as? Int, w > 0, h > 0 {
            imagePixelSize = CGSize(width: w, height: h)
        }

        guard let info = MetalPreviewPool.shared.textureInfo(for: id) else { return }
        applyTexture(info, for: id)
    }

    private func applyTexture(_ info: MetalPreviewPool.TextureInfo, for id: UUID) {
        guard id == boundPhotoID else { return }
        guard info.generation == 0 || info.generation == boundGeneration else { return }
        currentTexture = info.texture
        imagePixelSize = CGSize(width: info.pixelWidth, height: info.pixelHeight)
        rebuildVertices()
        requestDraw()
    }

    private func updateMatte(dark: Bool) {
        if dark {
            matteRed = 86 / 255; matteGreen = 86 / 255; matteBlue = 84 / 255
        } else {
            matteRed = 246 / 255; matteGreen = 246 / 255; matteBlue = 244 / 255
        }
    }

    private func updateMatteFromAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        updateMatte(dark: isDark)
    }

    private func requestDraw() {
        needsRedraw = true
        drawFrame()
    }

    private func rebuildVertices() {
        guard metalAvailable, let device else { return }
        let drawable = CGSize(
            width: max(metalLayer.drawableSize.width, 1),
            height: max(metalLayer.drawableSize.height, 1)
        )
        let fitted = AspectFitGeometry.fit(imageSize: imagePixelSize, drawableSize: drawable)
        let quad = AspectFitGeometry.metalQuad(for: fitted)
        var interleaved: [Float] = []
        interleaved.reserveCapacity(16)
        for i in 0..<4 {
            interleaved.append(quad.positions[i].x)
            interleaved.append(quad.positions[i].y)
            interleaved.append(quad.uvs[i].x)
            interleaved.append(quad.uvs[i].y)
        }
        vertexBuffer = device.makeBuffer(
            bytes: interleaved,
            length: interleaved.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }

    private func buildPipeline() {
        guard let device else { return }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct VIn { float2 position; float2 uv; };
        struct VOut { float4 position [[position]]; float2 uv; };
        vertex VOut vertex_main(const device VIn* verts [[buffer(0)]], uint vid [[vertex_id]]) {
            VIn in = verts[vid];
            VOut o;
            o.position = float4(in.position, 0, 1);
            o.uv = in.uv;
            return o;
        }
        fragment float4 fragment_main(VOut in [[stage_in]],
                                      texture2d<float> tex [[texture(0)]],
                                      sampler samp [[sampler(0)]]) {
            return tex.sample(samp, in.uv);
        }
        """
        do {
            let library = try device.makeLibrary(source: source, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "vertex_main")
            desc.fragmentFunction = library.makeFunction(name: "fragment_main")
            desc.colorAttachments[0].pixelFormat = ImagePixelFormat.metalPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
            let sdesc = MTLSamplerDescriptor()
            sdesc.minFilter = .linear
            sdesc.magFilter = .linear
            sampler = device.makeSamplerState(descriptor: sdesc)
        } catch {
            assertionFailure("Metal pipeline failed: \(error)")
        }
    }

    private func drawFrame() {
        guard metalAvailable else { return }
        guard needsRedraw else { return }
        guard let pipeline, let sampler, let queue,
              let drawable = metalLayer.nextDrawable(),
              let vertexBuffer else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: matteRed, green: matteGreen, blue: matteBlue, alpha: 1)

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        if let texture = currentTexture {
            enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            enc.setFragmentTexture(texture, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
        needsRedraw = false

        if currentTexture != nil, let t = pendingPhotonTime {
            onPhotonPresent?(t)
            pendingPhotonTime = nil
        }
    }
}

struct MetalBrowseCanvas: NSViewRepresentable {
    var photoID: UUID?
    var jpegPath: String?
    var imageSize: CGSize?
    var generation: UInt64 = 0
    var photonInputTime: CFAbsoluteTime?
    var matteIsDark: Bool = false
    var onPhotonPresent: ((CFAbsoluteTime) -> Void)?

    func makeNSView(context: Context) -> MetalBrowseNSView {
        MetalCanvasLifecycle.recordMake()
        let view = MetalBrowseNSView(frame: .zero)
        view.onPhotonPresent = onPhotonPresent
        return view
    }

    func updateNSView(_ nsView: MetalBrowseNSView, context: Context) {
        nsView.onPhotonPresent = onPhotonPresent
        nsView.bind(
            photoID: photoID,
            jpegPath: jpegPath,
            imageSize: imageSize,
            generation: generation,
            photonInputTime: photonInputTime,
            matteIsDark: matteIsDark
        )
    }
}

@MainActor
enum MetalCanvasLifecycle {
    private static var makeCount = 0

    static func beginSession() {
        makeCount = 0
    }

    static func recordMake() {
        makeCount += 1
        assert(makeCount == 1, "MetalBrowseCanvas.makeNSView ran more than once in one session")
    }
}
