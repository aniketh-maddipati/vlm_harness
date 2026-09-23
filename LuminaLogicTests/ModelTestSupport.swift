import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Lumina

/// Holds requests at the door until a test opens it. No sleeps, no polling: a test
/// awaits "N requests have arrived", acts, then opens the gate. Deterministic.
final class ModelGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var arrived: Int {
        lock.lock(); defer { lock.unlock() }
        return arrivals
    }

    /// Releases everything waiting now and everything that arrives later.
    func open() {
        lock.lock()
        opened = true
        let released = waiters
        waiters = []
        lock.unlock()
        released.forEach { $0.resume() }
    }

    /// Called by the transport before each send.
    func pass() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            arrivals += 1
            let ready = arrivalWaiters.filter { $0.count <= arrivals }
            arrivalWaiters.removeAll { $0.count <= arrivals }
            let isOpen = opened
            if !isOpen { waiters.append(continuation) }
            lock.unlock()
            ready.forEach { $0.continuation.resume() }
            if isOpen { continuation.resume() }
        }
    }

    /// Resumes once `count` sends have reached the gate.
    func waitForArrivals(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if arrivals >= count {
                lock.unlock()
                continuation.resume()
                return
            }
            arrivalWaiters.append((count, continuation))
            lock.unlock()
        }
    }
}

/// Stands in for a model server: replies from a script and records every request,
/// so a test can assert both what came back and what was sent — without a socket.
final class FakeModelTransport: ModelTransport, @unchecked Sendable {
    struct Unreachable: Error {}

    enum Outcome {
        /// The assistant's message content, wrapped in a chat-completions envelope.
        case content(String)
        case raw(Data, status: Int)
        case unreachable
    }

    private let lock = NSLock()
    private var script: [Outcome]
    private var requests: [URLRequest] = []
    private var inFlight = 0
    private(set) var peakInFlight = 0
    let gate: ModelGate?

    init(_ script: [Outcome], gate: ModelGate? = nil) {
        self.script = script
        self.gate = gate
    }
    convenience init(content: String) { self.init([.content(content)]) }
    static var unreachable: FakeModelTransport { FakeModelTransport([.unreachable]) }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.lock()
        inFlight += 1
        peakInFlight = max(peakInFlight, inFlight)
        lock.unlock()
        defer { lock.lock(); inFlight -= 1; lock.unlock() }

        if let gate { await gate.pass() }

        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        guard !script.isEmpty else { throw Unreachable() }
        switch script.removeFirst() {
        case .content(let text):
            let envelope: [String: Any] = ["choices": [["message": ["content": text]]]]
            return (try JSONSerialization.data(withJSONObject: envelope), 200)
        case .raw(let data, let status):
            return (data, status)
        case .unreachable:
            throw Unreachable()
        }
    }

    var sentRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    /// Decoded JSON body of the most recent request.
    var lastBody: [String: Any]? {
        guard let data = sentRequests.last?.httpBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

enum ModelTestSupport {
    static func makeAsset(
        id: UUID = UUID(),
        filename: String? = nil,
        recipe: EditRecipe? = nil,
        source: RecipeSource = .shot,
        stats: ImageStats? = nil,
        cull: CullDecision = .undecided,
        capturedAt: Date? = nil,
        embedding: [Float]? = nil,
        handRecipe: EditRecipe? = nil,
        thumbPath: String? = nil
    ) -> AssetRecord {
        let name = filename ?? "\(id.uuidString).ARW"
        return AssetRecord(
            id: id,
            sourceKey: "k-\(id.uuidString)",
            source: SourceReference(
                originalPath: "/proof/\(name)",
                relativePath: name,
                volumeID: "PROOF",
                availability: .available
            ),
            filename: name,
            cull: cull,
            recipe: recipe,
            capturedAt: capturedAt,
            thumbPath: thumbPath,
            embedding: embedding,
            recipeSource: source,
            handRecipe: handRecipe,
            imageStats: stats
        )
    }

    /// Flat histogram unless bins are given; mid-tone unless told otherwise.
    static func stats(
        mean: Double = AutoDevelop.meanAnchor,
        low: Double = 0,
        high: Double = 0,
        nativeTemperature: Double? = nil,
        bins: [Int]? = nil
    ) -> ImageStats {
        ImageStats(
            luminanceBins: bins ?? Array(repeating: 32, count: ImageStats.binCount),
            shadowClipFraction: low,
            highlightClipFraction: high,
            mean: mean,
            nativeTemperature: nativeTemperature,
            horizonAngle: nil
        )
    }

    /// A histogram with all its weight in one bin — two of these with different bins
    /// are maximally far apart, two with the same bin are identical.
    static func spikeBins(at index: Int) -> [Int] {
        var bins = Array(repeating: 0, count: ImageStats.binCount)
        bins[min(max(index, 0), ImageStats.binCount - 1)] = 1024
        return bins
    }

    /// A model reply that proposes one small, in-band contrast move.
    static let mildProposal = """
    {"exposure":0,"contrast":10,"highlights":0,"shadows":0,"vibrance":0,"saturation":0,
     "temperature_shift":0,"tint_shift":0}
    """

    /// A real JPEG on disk so `ModelImage.jpeg` has something to read; the model path
    /// can then be exercised end to end through a fake transport.
    static func writeTinyJPEG() throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumina-model-\(UUID().uuidString).jpg")
        let size = 8
        var pixels = [UInt8](repeating: 128, count: size * size * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 255 }
        guard let context = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url.path
    }
}
