import Foundation
import Testing
@testable import SwiftMCP

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

@Suite("StreamableHTTPTransport Tests", .serialized)
struct StreamableHTTPTransportTests {
    @Test("Initialization sets correct state")
    func testInitialization() async throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        let config = StreamableHTTPConfiguration(endpoint: endpoint)
        let mockSession = makeMockSession()
        let transport = StreamableHTTPTransport(configuration: config, session: mockSession)

        #expect(await transport.configuration == config.transport)
        #expect(await transport.state == .disconnected)
    }

    @Test("Start establishes SSE connection")
    func testStart() async throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        MockURLProtocol.requestHandler = { request in
            let data = "data: {\"jsonrpc\":\"2.0\",\"method\":\"ping\"}\n\n".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, data)
        }

        let config = StreamableHTTPConfiguration(endpoint: endpoint)
        let mockSession = makeMockSession()
        let transport = StreamableHTTPTransport(configuration: config, session: mockSession)

        let stateStream = try await transport.stateMessages
        var states: [TransportState] = []
        let monitorTask = Task {
            for await state in stateStream {
                states.append(state)
            }
        }

        try await transport.start()

        #expect(states.contains(.connecting))
        #expect(await transport.state == .connected)

        await transport.stop()
        monitorTask.cancel()
    }

    @Test("Stop cleans up resources")
    func testStop() async throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        MockURLProtocol.requestHandler = { request in
            let data = "data: {\"jsonrpc\":\"2.0\",\"method\":\"ping\"}\n\n".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, data)
        }

        let config = StreamableHTTPConfiguration(endpoint: endpoint)
        let mockSession = makeMockSession()
        let transport = StreamableHTTPTransport(configuration: config, session: mockSession)

        try await transport.start()
        await transport.stop()

        #expect(await transport.state == .disconnected)
    }

    @Test("Send message with notifications")
    func testSendNotification() async throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        var state = 0
        MockURLProtocol.requestHandler = { request in
            if state == 0 {
                state += 1
                let data = "data: {\"jsonrpc\":\"2.0\",\"method\":\"ping\"}\n\n".data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
                return (response, data)
            } else {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 202,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data())
            }
        }

        let config = StreamableHTTPConfiguration(endpoint: endpoint)
        let mockSession = makeMockSession()
        let transport = StreamableHTTPTransport(configuration: config, session: mockSession)

        try await transport.start()

        let notification = JSONRPCMessage.notification(
            TestNotification(params: ["key": AnyCodable("value")])
        )

        try await transport.send(notification)
        await transport.stop()
    }

    @Test("Send message with request - immediate response")
    func testSendRequest() async throws {
        let endpoint = URL(string: "https://example.com/mcp")!

        // Create a proper JSON-RPC response
        let jsonResponse: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "test-id",
            "result": [
                "result": "success"
            ]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: jsonResponse)

        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount == 1 {
                // Initial SSE connection
                let data = "data: {\"jsonrpc\":\"2.0\",\"method\":\"ping\"}\n\n".data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
                return (response, data)
            } else {
                // Immediate JSON response
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, encoded)
            }
        }

        let config = StreamableHTTPConfiguration(endpoint: endpoint)
        let mockSession = makeMockSession()
        let transport = StreamableHTTPTransport(configuration: config, session: mockSession)

        // Setup message stream before starting transport
        let messageStream = try await transport.messages
        var receivedMessages: [JSONRPCMessage] = []
        let messageTask = Task {
            for try await message in messageStream {
                receivedMessages.append(message)
                if receivedMessages.count == 1 {
                    break
                }
            }
        }

        try await transport.start()

        let request = JSONRPCMessage.request(
            id: .string("test-id"),
            request: TestRequest()
        )
        try await transport.send(request)

        // Wait for message processing
        try await Task.sleep(for: .milliseconds(100))

        #expect(!receivedMessages.isEmpty)
        if case let .response(id, _) = receivedMessages.first {
            #expect(id == .string("test-id"))
        }

        await transport.stop()
        messageTask.cancel()
    }

    @Test("Send message with request - SSE response")
    func testSendRequestWithSSEResponse() async throws {
        let endpoint = URL(string: "https://example.com/mcp")!

        // Create a proper JSON-RPC response
        let jsonResponse: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "test-id",
            "result": [
                "result": "success"
            ]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: jsonResponse)

        var requestCount = 0
        var sseResponseSent = false
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount == 1 {
                // Initial SSE connection
                let data = "data: {\"jsonrpc\":\"2.0\",\"method\":\"ping\"}\n\n".data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
                return (response, data)
            } else if !sseResponseSent {
                // Accept request and indicate response will come via SSE
                sseResponseSent = true
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 202,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!

                // Format SSE response with proper line endings
                let jsonString = String(data: encoded, encoding: .utf8)!
                let sseData = [
                    "data: \(jsonString)",
                    "",
                    ""
                ].joined(separator: "\n").data(using: .utf8)!

                return (response, sseData)
            } else {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
                return (response, Data())
            }
        }

        let config = StreamableHTTPConfiguration(endpoint: endpoint)
        let mockSession = makeMockSession()
        let transport = StreamableHTTPTransport(configuration: config, session: mockSession)

        // Setup message stream before starting transport
        let messageStream = try await transport.messages
        var receivedMessages: [JSONRPCMessage] = []
        let messageTask = Task {
            for try await message in messageStream {
                receivedMessages.append(message)
                if receivedMessages.count == 1 {
                    break
                }
            }
        }

        try await transport.start()

        let request = JSONRPCMessage.request(
            id: .string("test-id"),
            request: TestRequest()
        )
        try await transport.send(request)

        // Wait for message processing
        try await Task.sleep(for: .milliseconds(100))

        #expect(!receivedMessages.isEmpty)
        if case let .response(id, _) = receivedMessages.first {
            #expect(id == .string("test-id"))
        }

        await transport.stop()
        messageTask.cancel()
    }

    @Test("Handle retry policy")
    func testRetryPolicy() async throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        var attempts = 0

        MockURLProtocol.requestHandler = { request in
            let data = "data: {\"jsonrpc\":\"2.0\",\"method\":\"ping\"}\n\n".data(using: .utf8)!
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            if attempts > 0 {
                throw TransportError.operationFailed("Test error")
            }
            return (response, data)
        }

        let config = TransportConfiguration(
            retryPolicy: TransportRetryPolicy(maxAttempts: 3, baseDelay: 0.1)
        )
        let httpConfig = StreamableHTTPConfiguration(endpoint: endpoint, transport: config)
        let transport = StreamableHTTPTransport(
            configuration: httpConfig, session: makeMockSession())

        try await transport.start()

        do {
            try await transport.withRetry(operation: "test") {
                attempts += 1
                throw TransportError.operationFailed("Test error")
            }
            Issue.record("Expected retry failure")
        } catch {
            #expect(attempts == 3)
        }

        await transport.stop()
    }
}
