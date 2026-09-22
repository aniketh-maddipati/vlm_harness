import AppKit
import CoreImage
import Metal
import MetalKit
import os
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
    var onDrawableSizeChange: ((CGSize) -> Void)?
    var onBackingScaleChange: ((CGFloat) -> Void)?

    func makeCoordinator() -> Renderer {
        Renderer(
            onDrawableSizeChange: onDrawableSizeChange,
            onBackingScaleChange: onBackingScaleChange
        )
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        // SDR BGRA8 — matches DevelopColorPolicy display blit. rgba16Float with a
        // gamma display destination left linear values looking milky / white-cast.
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.delegate = context.coordinator
        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = false
            metalLayer.colorspace = DevelopColorPolicy.displayColorSpace
        }
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.image = image
        context.coordinator.zoom = zoom
        context.coordinator.panOffset = panOffset
        context.coordinator.onDrawableSizeChange = onDrawableSizeChange
        context.coordinator.onBackingScaleChange = onBackingScaleChange
        if let metalLayer = view.layer as? CAMetalLayer {
            let space = view.window?.screen?.colorSpace?.cgColorSpace
                ?? DevelopColorPolicy.displayColorSpace
            if metalLayer.colorspace !== space {
                metalLayer.colorspace = space
            }
        }
        view.needsDisplay = true
    }

    final class Renderer: NSObject, MTKViewDelegate {
        private static let signposter = OSSignposter(subsystem: "app.lumina.develop", category: "draw")

        let device: MTLDevice?
        private let commandQueue: MTLCommandQueue?
        private let context: CIContext

        var image: CIImage?
        var zoom: CGFloat = 1
        var panOffset: CGSize = .zero
        var onDrawableSizeChange: ((CGSize) -> Void)?
        var onBackingScaleChange: ((CGFloat) -> Void)?
        private var reportedDrawableSize = CGSize.zero

        init(
            onDrawableSizeChange: ((CGSize) -> Void)? = nil,
            onBackingScaleChange: ((CGFloat) -> Void)? = nil
        ) {
            let device = LuminaMetalDevice.shared
            self.device = device
            self.commandQueue = LuminaMetalDevice.commandQueue
            self.onDrawableSizeChange = onDrawableSizeChange
            self.onBackingScaleChange = onBackingScaleChange
            // Reuse the shared long-lived develop context — same working space
            // as the render graph; no per-frame context allocation.
            self.context = DevelopRenderGraph.sharedContext
            super.init()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            guard size != reportedDrawableSize else { return }
            reportedDrawableSize = size
            let backingScale = view.window?.backingScaleFactor ?? 1
            DispatchQueue.main.async { [weak self] in
                self?.onDrawableSizeChange?(size)
                self?.onBackingScaleChange?(backingScale)
            }
        }

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandQueue else { return }

            let drawableSize = view.drawableSize
            guard drawableSize.width > 1, drawableSize.height > 1 else { return }

            // A focus change may briefly have no pixels. Clear the persistent
            // drawable rather than leaving the previously focused photograph
            // resident on screen.
            if image == nil {
                guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
                let destination = CIRenderDestination(
                    width: Int(drawableSize.width),
                    height: Int(drawableSize.height),
                    pixelFormat: view.colorPixelFormat,
                    commandBuffer: commandBuffer
                ) { drawable.texture }
                destination.colorSpace = (view.layer as? CAMetalLayer)?.colorspace
                    ?? DevelopColorPolicy.displayColorSpace
                destination.isFlipped = true
                do {
                    _ = try context.startTask(toClear: destination)
                } catch {
                    return
                }
                commandBuffer.present(drawable)
                commandBuffer.commit()
                return
            }

            guard let image else { return }

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

            // Final display conversion — tagged the same on destination and layer
            // so AppKit does not re-interpret gamma-encoded pixels as linear.
            let displaySpace = (view.layer as? CAMetalLayer)?.colorspace
                ?? view.window?.screen?.colorSpace?.cgColorSpace
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
            // MTKView presents top-down; Core Image is bottom-up. This is the
            // only Y conversion on the present path. Incoming images must already
            // be EXIF-baked / origin-normalized (`OrientedDisplayImage`).
            destination.isFlipped = true

            let signpostID = Self.signposter.makeSignpostID()
            let drawState = Self.signposter.beginInterval("draw", id: signpostID)
            let started = CFAbsoluteTimeGetCurrent()
            do {
                _ = try context.startTask(toClear: destination)
                _ = try context.startTask(toRender: positioned, to: destination)
            } catch {
                Self.signposter.endInterval("draw", drawState)
                return
            }
            Self.signposter.endInterval("draw", drawState)
            // Record GPU completion, not command encoding. The signpost above
            // still brackets the requested Core Image startTask pair; this
            // metric is the honest slider-to-pixels cost.
            DevelopRenderCounters.recordMetalPresent()
            commandBuffer.addCompletedHandler { _ in
                LatencyMetrics.record(
                    LatencyMetrics.editDrawKey,
                    milliseconds: (CFAbsoluteTimeGetCurrent() - started) * 1000
                )
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
