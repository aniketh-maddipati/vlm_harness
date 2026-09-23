import XCTest
@testable import Lumina

/// D67 / R-N.1 — model inference is loopback-only, and the client that reaches it.
final class ModelClientTests: XCTestCase {

    // MARK: - Loopback guard (the half the lint can't see)

    func testEndpointAcceptsEveryLoopbackSpelling() {
        for host in ["http://127.0.0.1:1234/v1", "http://localhost:1234/v1", "http://[::1]:1234/v1",
                     "https://127.0.0.1/v1", "HTTP://LOCALHOST:1234/v1"] {
            let url = URL(string: host)!
            XCTAssertNotNil(
                ModelEndpoint(baseURL: url, model: "m", timeout: 1),
                "\(host) is loopback and must be accepted"
            )
        }
    }

    func testEndpointRefusesAnythingThatIsNotLoopback() {
        for host in ["https://api.openai.com/v1", "http://10.0.0.5:1234/v1", "http://192.168.1.20/v1",
                     "http://127.0.0.1.evil.example/v1", "http://localhost.example.com/v1",
                     "ftp://127.0.0.1/v1", "file:///tmp/x"] {
            let url = URL(string: host)!
            XCTAssertNil(
                ModelEndpoint(baseURL: url, model: "m", timeout: 1),
                "\(host) must be refused — the type cannot represent an off-machine endpoint"
            )
        }
    }

    func testNonLoopbackOverrideIsRefusedAndTheDefaultStands() {
        let endpoint = ModelEndpoint.loopbackEndpoint(
            overrideURL: "https://api.openai.com/v1",
            defaultURL: "http://127.0.0.1:1234/v1",
            model: "m",
            timeout: 1
        )
        XCTAssertEqual(endpoint.baseURL.absoluteString, "http://127.0.0.1:1234/v1",
                       "an override naming an off-machine host is refused, not honored")
    }

    func testLoopbackOverrideIsHonored() {
        let endpoint = ModelEndpoint.loopbackEndpoint(
            overrideURL: "http://localhost:9999/v1",
            defaultURL: "http://127.0.0.1:1234/v1",
            model: "m",
            timeout: 1
        )
        XCTAssertEqual(endpoint.baseURL.absoluteString, "http://localhost:9999/v1")
    }

    func testMalformedOverrideFallsBackToTheDefault() {
        let endpoint = ModelEndpoint.loopbackEndpoint(
            overrideURL: "not a url at all",
            defaultURL: "http://127.0.0.1:1234/v1",
            model: "m",
            timeout: 1
        )
        XCTAssertTrue(ModelEndpoint.isLoopback(endpoint.baseURL))
    }

    func testShippedEndpointsAreLoopback() {
        XCTAssertTrue(ModelEndpoint.isLoopback(ModelEndpoint.localVision.baseURL))
        XCTAssertTrue(ModelEndpoint.isLoopback(ModelEndpoint.localText.baseURL))
    }

    // MARK: - Client

    private func client(_ transport: FakeModelTransport) -> ChatCompletionsClient {
        ChatCompletionsClient(
            endpoint: ModelEndpoint(baseURL: URL(string: "http://127.0.0.1:1234/v1")!, model: "m", timeout: 1)!,
            transport: transport
        )
    }

    func testNoAuthorizationHeaderIsEverSent() async throws {
        let transport = FakeModelTransport(content: "{\"a\":1}")
        _ = try await client(transport).completeJSON(
            system: "s", user: "u", schemaName: "t", schemaJSON: "{\"type\":\"object\"}"
        )
        let request = try XCTUnwrap(transport.sentRequests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"),
                     "there is no key to send — the field no longer exists on the endpoint")
        XCTAssertEqual(request.url?.host, "127.0.0.1")
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
    }

    func testRequestCarriesTheSchemaAndAnImageOnlyWhenGiven() async throws {
        let transport = FakeModelTransport([.content("{\"a\":1}"), .content("{\"a\":1}")])
        let c = client(transport)
        _ = try await c.completeJSON(system: "s", user: "u", schemaName: "t", schemaJSON: "{\"type\":\"object\"}")
        var body = try XCTUnwrap(transport.lastBody)
        var messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        var content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1, "text only: no image part unless one was supplied")
        XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_schema")

        _ = try await c.completeJSON(
            system: "s", user: "u", imageJPEG: Data([0xFF, 0xD8]),
            schemaName: "t", schemaJSON: "{\"type\":\"object\"}"
        )
        body = try XCTUnwrap(transport.lastBody)
        messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[1]["type"] as? String, "image_url")
    }

    func testFencedOrProseWrappedJSONStillParses() async throws {
        let transport = FakeModelTransport(content: "Sure! ```json\n{\"exposure\": 0.5}\n``` hope that helps")
        let json = try await client(transport).completeJSON(
            system: "s", user: "u", schemaName: "t", schemaJSON: "{\"type\":\"object\"}"
        )
        XCTAssertEqual((json["exposure"] as? NSNumber)?.doubleValue, 0.5)
    }

    func testHTTPErrorCarriesTheServerMessageNeverTheRequest() async {
        let body = "{\"error\":{\"message\":\"model not loaded\"}}".data(using: .utf8)!
        let transport = FakeModelTransport([.raw(body, status: 404)])
        do {
            _ = try await client(transport).completeJSON(
                system: "SECRET-SYSTEM", user: "SECRET-USER", schemaName: "t", schemaJSON: "{\"type\":\"object\"}"
            )
            XCTFail("a 404 must throw")
        } catch let error as ModelClientError {
            XCTAssertEqual(error, .http(status: 404, message: "model not loaded"))
            XCTAssertFalse("\(error)".contains("SECRET"), "error text must never echo the request")
        } catch {
            XCTFail("unexpected error type \(error)")
        }
    }

    func testEmptyAndNonJSONRepliesAreDistinctFailures() async {
        do {
            _ = try await client(FakeModelTransport(content: "")).completeJSON(
                system: "s", user: "u", schemaName: "t", schemaJSON: "{\"type\":\"object\"}"
            )
            XCTFail()
        } catch { XCTAssertEqual(error as? ModelClientError, .emptyResponse) }

        do {
            _ = try await client(FakeModelTransport(content: "no braces here")).completeJSON(
                system: "s", user: "u", schemaName: "t", schemaJSON: "{\"type\":\"object\"}"
            )
            XCTFail()
        } catch { XCTAssertEqual(error as? ModelClientError, .notJSON) }
    }

    func testUnreachableTransportSurfacesAsAnError() async {
        do {
            _ = try await client(.unreachable).completeJSON(
                system: "s", user: "u", schemaName: "t", schemaJSON: "{\"type\":\"object\"}"
            )
            XCTFail()
        } catch {
            XCTAssertTrue(error is FakeModelTransport.Unreachable)
        }
    }
}
