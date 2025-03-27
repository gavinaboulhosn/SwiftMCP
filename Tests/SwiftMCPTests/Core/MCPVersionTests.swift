import Foundation
import Testing

@testable import SwiftMCP

@Suite("MCP Version Tests")
struct MCPVersionTests {
    @Test("Version Format Validation")
    func testVersionFormat() async throws {
        // Test valid version format
        #expect(MCPVersion.isValidFormat("2025-03-26"))

        // Test invalid formats
        #expect(!MCPVersion.isValidFormat(""))
        #expect(!MCPVersion.isValidFormat("2025/03/26"))
        #expect(!MCPVersion.isValidFormat("2025-13-45"))
        #expect(!MCPVersion.isValidFormat("invalid"))
        #expect(!MCPVersion.isValidFormat("2025-3-26"))
        #expect(!MCPVersion.isValidFormat("2025-03-6"))
        #expect(!MCPVersion.isValidFormat("2025-02-31"))  // Invalid date
    }

    @Test("Version Support")
    func testVersionSupport() async throws {
        // Test current version
        #expect(MCPVersion.isSupported("2025-03-26"))

        // Test previous versions
        #expect(MCPVersion.isSupported("2024-11-05"))

        // Test unsupported versions
        #expect(!MCPVersion.isSupported("2023-01-01"))
        #expect(!MCPVersion.isSupported("2025-12-31"))
        #expect(!MCPVersion.isSupported("invalid"))
    }

    @Test("Version Comparison")
    func testVersionComparison() async throws {
        // Test equal versions
        #expect(MCPVersion.compare("2025-03-26", "2025-03-26") == .orderedSame)

        // Test ordered versions
        #expect(MCPVersion.compare("2024-11-05", "2025-03-26") == .orderedAscending)
        #expect(MCPVersion.compare("2025-03-26", "2024-11-05") == .orderedDescending)

        // Test invalid versions
        #expect(MCPVersion.compare("invalid", "2025-03-26") == .orderedSame)
        #expect(MCPVersion.compare("2025-03-26", "invalid") == .orderedSame)
        #expect(MCPVersion.compare("invalid", "invalid") == .orderedSame)
    }

    @Test("Feature Support")
    func testFeatureSupport() async throws {
        // Test 2025-03-26 features
        #expect(MCPVersion.supportsFeature(.completions, version: "2025-03-26"))
        #expect(MCPVersion.supportsFeature(.audioContent, version: "2025-03-26"))
        #expect(MCPVersion.supportsFeature(.toolAnnotations, version: "2025-03-26"))
        #expect(MCPVersion.supportsFeature(.batchRequests, version: "2025-03-26"))

        // Test 2024-11-05 features (should not support new features)
        #expect(!MCPVersion.supportsFeature(.completions, version: "2024-11-05"))
        #expect(!MCPVersion.supportsFeature(.audioContent, version: "2024-11-05"))
        #expect(!MCPVersion.supportsFeature(.toolAnnotations, version: "2024-11-05"))
        #expect(!MCPVersion.supportsFeature(.batchRequests, version: "2024-11-05"))

        // Test invalid version
        #expect(!MCPVersion.supportsFeature(.completions, version: "invalid"))
    }

    @Test("Version Negotiation")
    func testVersionNegotiation() async throws {
        let negotiation = MCPVersion.VersionNegotiation()

        // Test negotiation with supported version
        let negotiated1 = negotiation.negotiate(serverVersion: "2025-03-26")
        #expect(negotiated1 == "2025-03-26")

        // Test negotiation with older supported version
        let negotiated2 = negotiation.negotiate(serverVersion: "2025-03-26")
        #expect(negotiated2 == "2025-03-26")

        // Test negotiation with unsupported version
        let negotiated3 = negotiation.negotiate(serverVersion: "invalid")
        #expect(negotiated3 == nil)
    }

    @Test("Feature Set")
    func testFeatureSet() async throws {
        let latest = MCPVersion.FeatureSet(version: "2025-03-26")
        let older = MCPVersion.FeatureSet(version: "2024-11-05")

        // Test latest version features
        #expect(latest.supports(.completions))
        #expect(latest.supports(.audioContent))
        #expect(latest.supports(.toolAnnotations))
        #expect(latest.supports(.batchRequests))

        // Test older version features
        #expect(!older.supports(.completions))
        #expect(!older.supports(.audioContent))
        #expect(!older.supports(.toolAnnotations))
        #expect(!older.supports(.batchRequests))

        // Test common features
        let common = MCPVersion.FeatureSet.commonFeatures("2025-03-26", "2024-11-05")
        #expect(common.isEmpty)
    }

    @Test("Client Version Negotiation")
    func testClientVersionNegotiation() async throws {
        let client = MCPClient(
            clientInfo: Implementation(name: "test", version: "1.0.0")
        )

        // Test negotiation down to older version
        let mockNegotiate = MockTransport()
        var initCount = 0
        await mockNegotiate.setResponseHandler { message in
            switch message {
            case let .request(id, request):
                guard let initRequest = request as? InitializeRequest else {
                    Issue.record("Expected InitializeRequest")
                    return nil
                }

                initCount += 1
                let result = InitializeResult(
                    capabilities: .init(),
                    protocolVersion: "2024-11-05",
                    serverInfo: .init(name: "mock", version: "1.0.0")
                )

                let encoder = JSONEncoder()
                let decoder = JSONDecoder()
                let encoded = try! encoder.encode(result)
                let decoded = try! decoder.decode(AnyCodable.self, from: encoded)

                return .response(id: id, response: decoded)

            case .notification:
                return nil

            default:
                Issue.record("Unexpected message type")
                return nil
            }
        }

        try await client.start(mockNegotiate)
        #expect(initCount == 1)  // Initial request
        let isConnected = await client.isConnected
        #expect(isConnected)
    }
}

// MARK: - Mock Transport

private actor MockTransport: MCPTransport {
    var configuration: TransportConfiguration = TransportConfiguration()
    var state: TransportState = .disconnected

    private var responseHandler: ((JSONRPCMessage) -> JSONRPCMessage?)?

    private let messageStream: AsyncThrowingStream<JSONRPCMessage, Error>
    private let messageContinuation: AsyncThrowingStream<JSONRPCMessage, Error>.Continuation

    private let stateStream: AsyncStream<TransportState>
    private let stateContinuation: AsyncStream<TransportState>.Continuation

    init() {
        (stateStream, stateContinuation) = AsyncStream.makeStream(of: TransportState.self)
        (messageStream, messageContinuation) = AsyncThrowingStream.makeStream()
    }

    func start() async throws {
        state = .connected
        stateContinuation.yield(state)
    }

    func stop() {
        state = .disconnected
        stateContinuation.yield(state)
        messageContinuation.finish()
    }

    func send(_ message: JSONRPCMessage, timeout: TimeInterval? = nil) async throws {
        if let response = responseHandler?(message) {
            messageContinuation.yield(response)
        }
    }

    var messages: AsyncThrowingStream<JSONRPCMessage, Error> {
        messageStream
    }

    var stateMessages: AsyncStream<TransportState> {
        stateStream
    }

    // Actor-safe methods for test access
    func setResponseHandler(_ handler: @escaping (JSONRPCMessage) -> JSONRPCMessage?) {
        responseHandler = handler
    }
}
