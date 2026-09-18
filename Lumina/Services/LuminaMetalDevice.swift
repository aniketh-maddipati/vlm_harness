import Metal

/// Shared Metal device for browse + develop surfaces — one GPU context per process.
nonisolated enum LuminaMetalDevice {
    static let shared: MTLDevice? = MTLCreateSystemDefaultDevice()

    static let commandQueue: MTLCommandQueue? = shared?.makeCommandQueue()
}
