import AppKit
import Metal
import QuartzCore
import SwiftUI

/// CAMetalLayer-backed browse canvas — no decode/upload on main; photon measured at present.
final class MetalBrowseNSView: NSView {
    private let metalLayer = CAMetalLayer()
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?
    private var displayTimer: Timer?
    private var currentTexture: MTLTexture?
    private var boundPhotoID: UUID?
    private var pendingPhotonTime: CFAbsoluteTime?
    private var needsRedraw = true
    private let metalAvailable: Bool
    var onPhotonPresent: ((CFAbsoluteTime) -> Void)?

    override init(frame frameRect: NSRect) {
        let device = MetalPreviewPool.shared.device ?? MTLCreateSystemDefaultDevice()
        self.device = device
        self.queue = device?.makeCommandQueue()
        self.metalAvailable = device != nil && queue != nil
        super.init(frame: frameRect)
        wantsLayer = true
        guard metalAvailable, let device else {
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            return
        }
        layer = metalLayer
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        buildPipeline()
        startDisplayTimer()
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
        displayTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        guard metalAvailable else { return }
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(
            width: bounds.width * metalLayer.contentsScale,
            height: bounds.height * metalLayer.contentsScale
        )
        needsRedraw = true
    }

    func bind(photoID: UUID?, jpegPath: String?, photonInputTime: CFAbsoluteTime?) {
        boundPhotoID = photoID
        pendingPhotonTime = photonInputTime
        guard let photoID else {
            currentTexture = nil
            needsRedraw = true
            return
        }
        if let tex = MetalPreviewPool.shared.texture(for: photoID) {
            currentTexture = tex
            needsRedraw = true
            return
        }
        currentTexture = nil
        needsRedraw = true
        if let jpegPath {
            MetalPreviewPool.shared.scheduleUpload(id: photoID, jpegPath: jpegPath, distanceBias: 0)
        }
    }

    @objc private func textureReady(_ note: Notification) {
        guard let id = note.userInfo?["photoID"] as? UUID,
              id == boundPhotoID,
              let tex = MetalPreviewPool.shared.texture(for: id) else { return }
        currentTexture = tex
        needsRedraw = true
    }

    private func buildPipeline() {
        guard let device else { return }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 position [[position]]; float2 uv; };
        vertex VOut vertex_main(uint vid [[vertex_id]]) {
            float2 pos[4] = { float2(-1,-1), float2(1,-1), float2(-1,1), float2(1,1) };
            float2 uv[4]  = { float2(0,1), float2(1,1), float2(0,0), float2(1,0) };
            VOut o; o.position = float4(pos[vid], 0, 1); o.uv = uv[vid]; return o;
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
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
            let sdesc = MTLSamplerDescriptor()
            sdesc.minFilter = .linear
            sdesc.magFilter = .linear
            sampler = device.makeSamplerState(descriptor: sdesc)
        } catch {
            assertionFailure("Metal pipeline failed: \(error)")
        }
    }

    /// Main-runloop timer — CAMetalLayer ownership requires main; no CVDisplayLink→async hop.
    private func startDisplayTimer() {
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.drawFrame()
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func drawFrame() {
        guard metalAvailable else { return }
        guard needsRedraw || currentTexture != nil else { return }
        guard let pipeline, let sampler, let queue,
              let drawable = metalLayer.nextDrawable() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        if let texture = currentTexture {
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
    var photonInputTime: CFAbsoluteTime?
    var onPhotonPresent: ((CFAbsoluteTime) -> Void)?

    func makeNSView(context: Context) -> MetalBrowseNSView {
        let view = MetalBrowseNSView(frame: .zero)
        view.onPhotonPresent = onPhotonPresent
        return view
    }

    func updateNSView(_ nsView: MetalBrowseNSView, context: Context) {
        nsView.onPhotonPresent = onPhotonPresent
        // Never decode or upload here — bind texture if warm, else schedule background upload.
        nsView.bind(photoID: photoID, jpegPath: jpegPath, photonInputTime: photonInputTime)
    }
}
