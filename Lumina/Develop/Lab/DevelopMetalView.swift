import AppKit
import CoreImage
import Metal
import MetalKit
import SwiftUI

/// Metal-backed live preview for the Develop Lab.
///
/// The preview never crosses a `CGImage`/`NSImage` CPU boundary: the scheduler
/// publishes a `CIImage` and this view renders it straight into the drawable
/// with one final ColorSync conversion to the active display profile.
struct DevelopMetalView: NSViewRepresentable {
    var image: CIImage?
    var zoom: CGFloat = 1
    var panOffset: CGSize = .zero

    func makeCoordinator() -> Renderer { Renderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.framebufferOnly = false
        view.colorPixelFormat = .rgba16Float
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.delegate = context.coordinator
        // Interactive surfaces use half-float RGBA; conversion to the display
        // profile happens exactly once, here at the destination.
        (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = false
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.image = image
        context.coordinator.zoom = zoom
        context.coordinator.panOffset = panOffset
        view.needsDisplay = true
    }

    final class Renderer: NSObject, MTKViewDelegate {
        let device: MTLDevice?
        private let commandQueue: MTLCommandQueue?
        private let context: CIContext

        var image: CIImage?
        var zoom: CGFloat = 1
        var panOffset: CGSize = .zero

        override init() {
            let device = MTLCreateSystemDefaultDevice()
            self.device = device
            self.commandQueue = device?.makeCommandQueue()
            // Reuse the shared long-lived develop context — same working space
            // as the render graph; no per-frame context allocation.
            self.context = DevelopRenderGraph.sharedContext
            super.init()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let image,
                  let drawable = view.currentDrawable,
                  let commandQueue else { return }

            let drawableSize = view.drawableSize
            guard drawableSize.width > 1, drawableSize.height > 1 else { return }

            let extent = image.extent
            guard extent.width > 0, extent.height > 0 else { return }

            // Aspect-fit into the drawable, then optional 1:1 zoom + pan.
            let fit = min(drawableSize.width / extent.width, drawableSize.height / extent.height)
            let scale = fit * zoom
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let backing = view.window?.backingScaleFactor ?? 2
            let dx = (drawableSize.width - scaled.extent.width) / 2 + panOffset.width * backing
            let dy = (drawableSize.height - scaled.extent.height) / 2 - panOffset.height * backing
            let positioned = scaled.transformed(by: CGAffineTransform(
                translationX: dx - scaled.extent.origin.x,
                y: dy - scaled.extent.origin.y
            ))

            // Final display conversion — the active display profile, exactly once.
            let displaySpace = view.window?.screen?.colorSpace?.cgColorSpace
                ?? DevelopColorPolicy.displayColorSpace

            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
            // Encode CI work into this command buffer so present() is ordered
            // after rendering completes.
            let destination = CIRenderDestination(
                width: Int(drawableSize.width),
                height: Int(drawableSize.height),
                pixelFormat: view.colorPixelFormat,
                commandBuffer: commandBuffer
            ) { drawable.texture }
            destination.colorSpace = displaySpace
            destination.isFlipped = false

            do {
                _ = try context.startTask(toClear: destination)
                _ = try context.startTask(toRender: positioned, to: destination)
            } catch {
                return
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
