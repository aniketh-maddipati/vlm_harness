import Metal

/// Shared Metal device for browse + develop surfaces — one GPU context per process.
enum LuminaMetalDevice {
    static let shared: MTLDevice? = MTLCreateSystemDefaultDevice()

    static let commandQueue: MTLCommandQueue? = shared?.makeCommandQueue()
}
