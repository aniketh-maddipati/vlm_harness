import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Where a model lives. D67 (R-N.1): a loopback address and nothing else — a
/// model the operator runs on their own machine, reached over the
/// OpenAI-compatible `/v1/chat/completions` API that LM Studio serves.
///
/// There is no hosted provider and no API key anywhere in this type. The
/// capability was removed rather than defaulted off, so there is no flag to
/// flip and nothing to leak.
nonisolated struct ModelEndpoint: Sendable, Equatable {
    var baseURL: URL
    var model: String
    var timeout: TimeInterval

    /// Hosts that never leave the machine.
    static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

    /// `banned_patterns` catches non-loopback URL *literals*; it cannot see an
    /// environment override. This is the half that can.
    static func isLoopback(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return loopbackHosts.contains(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
    }

    /// Fails rather than builds an endpoint that could reach off the machine.
    init?(baseURL: URL, model: String, timeout: TimeInterval) {
        guard Self.isLoopback(baseURL) else { return nil }
        self.baseURL = baseURL
        self.model = model
        self.timeout = timeout
    }

    /// Reads an override, and **refuses** it when it names a non-loopback host —
    /// the compiled-in loopback default stands instead. Honoring it would make
    /// D67 a configuration promise rather than a code one.
    static func loopbackEndpoint(
        overrideURL: String?,
        defaultURL: String,
        model: String,
        timeout: TimeInterval
    ) -> ModelEndpoint {
        if let overrideURL, let url = URL(string: overrideURL),
           let endpoint = ModelEndpoint(baseURL: url, model: model, timeout: timeout) {
            return endpoint
        }
        // The default is a literal in this file, so it is loopback by construction
        // and linted as such; the force-unwrap cannot fire.
        return ModelEndpoint(baseURL: URL(string: defaultURL)!, model: model, timeout: timeout)!
    }

    /// Local Qwen2.5-VL served by LM Studio, for the auto pass. Nothing leaves the machine.
    static var localVision: ModelEndpoint {
        let env = ProcessInfo.processInfo.environment
        return loopbackEndpoint(
            overrideURL: env["LUMINA_AUTO_BASE_URL"],
            defaultURL: "http://127.0.0.1:1234/v1",
            model: env["LUMINA_AUTO_MODEL"] ?? "qwen2.5-vl-3b-instruct",
            timeout: 60
        )
    }

    /// Local Qwen2.5 text, for ask planning. Under D67 this replaces the hosted
    /// planner; `KeywordAskPlanner` remains the offline baseline beneath it.
    static var localText: ModelEndpoint {
        let env = ProcessInfo.processInfo.environment
        return loopbackEndpoint(
            overrideURL: env["LUMINA_ASK_BASE_URL"],
            defaultURL: "http://127.0.0.1:1234/v1",
            model: env["LUMINA_ASK_MODEL"] ?? "qwen2.5-3b-instruct",
            timeout: 30
        )
    }
}

/// The one network seam, so tests can stand in for a server without a socket.
protocol ModelTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

nonisolated struct URLSessionModelTransport: ModelTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

nonisolated enum ModelClientError: Error, Equatable, Sendable {
    case http(status: Int, message: String)
    case emptyResponse
    case notJSON
    /// The server sent more than any schema-constrained answer could need.
    case responseTooLarge(bytes: Int)
    /// Nested deeper than any schema-constrained answer could be. Refused before
    /// Foundation's recursive parser sees it — on some Foundation builds that is a
    /// stack overflow, not an error.
    case responseTooDeep(depth: Int)
}

/// Minimal OpenAI-compatible chat client: one system prompt, one user turn with
/// optional image, JSON back. Deliberately small — the product needs a structured
/// answer, not a conversation. "OpenAI-compatible" names the wire format that LM
/// Studio speaks; under D67 the only destination is loopback.
nonisolated struct ChatCompletionsClient: Sendable {
    let endpoint: ModelEndpoint
    let transport: any ModelTransport

    init(endpoint: ModelEndpoint, transport: any ModelTransport = URLSessionModelTransport()) {
        self.endpoint = endpoint
        self.transport = transport
    }

    /// `schemaJSON` is a JSON Schema object serialized as a string. LM Studio constrains
    /// decoding to it; the caller still validates what comes back.
    func completeJSON(
        system: String,
        user: String,
        imageJPEG: Data? = nil,
        schemaName: String,
        schemaJSON: String
    ) async throws -> [String: Any] {
        var content: [[String: Any]] = [["type": "text", "text": user]]
        if let imageJPEG {
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64," + imageJPEG.base64EncodedString()],
            ])
        }
        let schema = try JSONSerialization.jsonObject(with: Data(schemaJSON.utf8))
        let body: [String: Any] = [
            "model": endpoint.model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": content],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": schemaName, "strict": true, "schema": schema],
            ],
        ]

        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = endpoint.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, status) = try await transport.send(request)
        // Bounded before it is parsed: whoever is on the other end of the socket, a
        // schema-constrained answer is a few hundred bytes, never megabytes.
        guard data.count <= Self.maxResponseBytes else {
            throw ModelClientError.responseTooLarge(bytes: data.count)
        }
        let depth = Self.nestingDepth(of: data)
        guard depth <= Self.maxNestingDepth else {
            throw ModelClientError.responseTooDeep(depth: depth)
        }
        guard (200..<300).contains(status) else {
            throw ModelClientError.http(status: status, message: Self.errorMessage(in: data))
        }
        // An unparseable or non-object envelope is the client's own failure, not a
        // Foundation error leaking out: whoever is on the socket, "nothing usable came
        // back" is reported in one shape.
        guard let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choices = envelope["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String,
              !text.isEmpty else { throw ModelClientError.emptyResponse }
        // The answer is a JSON string inside the envelope, so its own nesting is
        // measured on its own: the envelope guard above never sees it.
        let contentDepth = Self.nestingDepth(of: Data(text.utf8))
        guard contentDepth <= Self.maxNestingDepth else {
            throw ModelClientError.responseTooDeep(depth: contentDepth)
        }
        guard let object = Self.firstJSONObject(in: text) else { throw ModelClientError.notJSON }
        return object
    }

    static let maxResponseBytes = 256 * 1024

    /// A schema-constrained answer is an object of scalars, at most a few levels of
    /// arrays inside; 32 leaves room for any envelope a compatible server wraps it in.
    static let maxNestingDepth = 32

    /// Deepest `{` / `[` nesting in the bytes, ignoring brackets inside strings. A
    /// linear scan, so it costs nothing next to the parse it protects, and it never
    /// recurses — which is the point.
    static func nestingDepth(of data: Data) -> Int {
        var depth = 0
        var deepest = 0
        var inString = false
        var escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                deepest = max(deepest, depth)
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth = max(0, depth - 1)
            default: break
            }
        }
        return deepest
    }

    /// Tolerates code fences or stray prose around the object — small local models
    /// sometimes add them even under a schema.
    static func firstJSONObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        let slice = Data(text[start...end].utf8)
        guard nestingDepth(of: slice) <= maxNestingDepth else { return nil }
        return (try? JSONSerialization.jsonObject(with: slice)) as? [String: Any]
    }

    /// Error text for a failed call, never the request — a request carries a photograph.
    private static func errorMessage(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data.prefix(200), encoding: .utf8) ?? ""
        }
        return message
    }
}

/// Small JPEG of a frame for a vision model: the cached preview, downscaled.
/// The RAW itself never leaves Lumina's decode path.
nonisolated enum ModelImage {
    static let longEdge = 512

    static func jpeg(forPreviewAt path: String, longEdge: Int = ModelImage.longEdge) -> Data? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: longEdge,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
