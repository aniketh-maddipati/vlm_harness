#if DEBUG
import Foundation
import Network

/// State Probe v2 — streaming NDJSON canonical state over a local TCP socket.
///
/// DEBUG / harness-only. Never compiled into Release. Bind address is loopback only
/// (zero egress). Mid-script clients may read the latest line or wait for generation bumps.
///
/// Schema: Scripts/harness/probe/schema.json
struct ProbeV2State: Codable, Equatable {
    struct Generation: Codable, Equatable {
        var records: Int
        var marks: Int
        var staging: Int
        var focus: Int
        var layout: Int
    }

    struct Record: Codable, Equatable {
        var id: String
        var row: Int
        var scene: Int
        var availability: String
    }

    struct Staging: Codable, Equatable {
        var active: Bool
        var ring: String
        var scopeCount: Int
        var excludedCount: Int
        var bannerCount: Int
        var headerCount: Int
        var receiptCount: Int
        var returnReleaseArmed: Bool
        var recipeKind: String?
    }

    struct Focus: Codable, Equatable {
        var assetId: String?
        var visible: Bool
        var armedControl: String?
    }

    var schemaVersion: Int = 2
    var tsMs: Int
    var generation: Generation
    var records: [Record]
    var marks: [String: String]
    var staging: Staging
    var focus: Focus
    var residentRungByFrame: [String: String]
    var undoDepth: Int
    var exportKeptCount: Int
    var chipPresent: Bool
    var fixture: String?
    var seed: String?
    var fakeClockMs: Int?
}

/// Loopback NDJSON server. One line per state publish.
@MainActor
final class StateProbeV2Server {
    static let shared = StateProbeV2Server()

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private(set) var port: NWEndpoint.Port?
    private var latestLine: Data = Data("{}\n".utf8)

    /// Start on an ephemeral loopback port. Returns the port number.
    @discardableResult
    func start(preferredPort: UInt16 = 0) throws -> UInt16 {
        if listener != nil, let port {
            return port.rawValue
        }
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: preferredPort) ?? .any)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.attach(connection)
            }
        }
        listener.start(queue: DispatchQueue(label: "lumina.probe.v2"))
        self.listener = listener
        // Wait briefly for port binding.
        let deadline = Date().addingTimeInterval(1)
        while listener.port == nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard let bound = listener.port else {
            throw NSError(domain: "StateProbeV2", code: 1, userInfo: [NSLocalizedDescriptionKey: "bind failed"])
        }
        self.port = bound
        fputs("[StateProbeV2] listening on 127.0.0.1:\(bound.rawValue)\n", stderr)
        return bound.rawValue
    }

    func stop() {
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        port = nil
    }

    func publish(_ state: ProbeV2State) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(state) else { return }
        data.append(0x0A)
        latestLine = data
        for connection in connections {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func attach(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: DispatchQueue(label: "lumina.probe.v2.conn"))
        // Send latest snapshot immediately so mid-script attaches are queryable.
        connection.send(content: latestLine, completion: .contentProcessed { _ in })
    }
}

enum ProbeV2Launch {
    static let portFlag = "--probe-v2-port"
    static let enableFlag = "--probe-v2"

    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains(enableFlag) || UITestSupport.isActive else { return }
        var preferred: UInt16 = 0
        if let idx = args.firstIndex(of: portFlag), args.indices.contains(idx + 1),
           let parsed = UInt16(args[idx + 1]) {
            preferred = parsed
        }
        do {
            _ = try StateProbeV2Server.shared.start(preferredPort: preferred)
        } catch {
            fputs("[StateProbeV2] failed to start: \(error)\n", stderr)
        }
    }
}
#endif
