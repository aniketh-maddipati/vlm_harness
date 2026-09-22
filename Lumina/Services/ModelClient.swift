import Foundation
import ImageIO
import Security
import UniformTypeIdentifiers

/// Where a model lives. Both providers speak the OpenAI-compatible
/// `/v1/chat/completions` API — LM Studio serves local models on it, OpenAI
/// serves hosted ones — so one client covers both and only the endpoint differs.
nonisolated struct ModelEndpoint: Sendable, Equatable {
    var baseURL: URL
    var model: String
    /// Nil for a local server that takes no key.
    var apiKey: String?
    var timeout: TimeInterval

    /// Local Qwen2.5-VL served by LM Studio. Nothing leaves the machine.
    /// Override with `LUMINA_AUTO_BASE_URL` / `LUMINA_AUTO_MODEL`.
    static var localVision: ModelEndpoint {
        let env = ProcessInfo.processInfo.environment
        return ModelEndpoint(
            baseURL: URL(string: env["LUMINA_AUTO_BASE_URL"] ?? "http://127.0.0.1:1234/v1")!,
            model: env["LUMINA_AUTO_MODEL"] ?? "qwen2.5-vl-3b-instruct",
            apiKey: nil,
            timeout: 60
        )
    }

    /// Hosted OpenAI, or nil when no key is available. The key comes from the
    /// Keychain entry `lumina.openai` first, then `OPENAI_API_KEY` — never from source.
    static var openAI: ModelEndpoint? {
        let env = ProcessInfo.processInfo.environment
        guard let key = KeychainSecret.read(service: KeychainSecret.openAIService)
            ?? env["OPENAI_API_KEY"],
            !key.isEmpty else { return nil }
        return ModelEndpoint(
            baseURL: URL(string: env["LUMINA_ASK_BASE_URL"] ?? "https://api.openai.com/v1")!,
            model: env["LUMINA_ASK_MODEL"] ?? "gpt-4o-mini",
            apiKey: key,
            timeout: 30
        )
    }
}

/// Reads a generic-password Keychain item stored with
/// `security add-generic-password -a "$USER" -s <service> -w`.
nonisolated enum KeychainSecret {
    static let openAIService = "lumina.openai"

    static func read(service: String, account: String = NSUserName()) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
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
}

/// Minimal OpenAI-compatible chat client: one system prompt, one user turn with
/// optional image, JSON back. Deliberately small — the product needs a structured
/// answer, not a conversation.
nonisolated struct ChatCompletionsClient: Sendable {
    let endpoint: ModelEndpoint
    let transport: any ModelTransport

    init(endpoint: ModelEndpoint, transport: any ModelTransport = URLSessionModelTransport()) {
        self.endpoint = endpoint
        self.transport = transport
    }

    /// `schemaJSON` is a JSON Schema object serialized as a string. Both LM Studio and
    /// OpenAI constrain decoding to it; the caller still validates what comes back.
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
        if let key = endpoint.apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, status) = try await transport.send(request)
        guard (200..<300).contains(status) else {
            throw ModelClientError.http(status: status, message: Self.errorMessage(in: data))
        }
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = envelope["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String,
              !text.isEmpty else { throw ModelClientError.emptyResponse }
        guard let object = Self.firstJSONObject(in: text) else { throw ModelClientError.notJSON }
        return object
    }

    /// Tolerates code fences or stray prose around the object — small local models
    /// sometimes add them even under a schema.
    static func firstJSONObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        let slice = Data(text[start...end].utf8)
        return (try? JSONSerialization.jsonObject(with: slice)) as? [String: Any]
    }

    /// Error text for a failed call, never the request — so a key can't leak into a log.
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
