import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Lumina

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

    init(_ script: [Outcome]) { self.script = script }
    convenience init(content: String) { self.init([.content(content)]) }
    static var unreachable: FakeModelTransport { FakeModelTransport([.unreachable]) }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
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
