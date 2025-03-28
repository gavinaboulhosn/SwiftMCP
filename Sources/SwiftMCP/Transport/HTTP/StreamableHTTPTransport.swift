import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "StreamableHTTPTransport")

/// Implementation of the MCP Streamable HTTP transport.
public actor StreamableHTTPTransport: RetryableTransport {
    // MARK: - Properties

    public private(set) var state: TransportState = .disconnected {
        didSet {
            let newState = state
            logger.info("Transport state update: \(oldValue) -> \(newState)")
            transportStateContinuation?.yield(with: .success(newState))
        }
    }

    public let configuration: TransportConfiguration

    private let httpConfig: StreamableHTTPConfiguration
    private let session: URLSessionProtocol
    private var activeStreams: [UUID: Task<Void, Error>] = [:]
    private var messageContinuation: AsyncThrowingStream<JSONRPCMessage, Error>.Continuation?
    private var transportStateContinuation: AsyncStream<TransportState>.Continuation?
    private var sessionID: String?
    private var lastEventID: String?
    private let parser = SSEParser()

    // MARK: - Initialization

    public init(configuration: StreamableHTTPConfiguration, session: URLSessionProtocol? = nil) {
        self.httpConfig = configuration
        self.configuration = configuration.transport
        self.session = session ?? URLSession(configuration: configuration.urlSessionConfiguration)
        logger.debug(
            "Initialized StreamableHTTPTransport with endpoint=\(configuration.endpoint.absoluteString)"
        )
    }

    deinit {
        for task in activeStreams.values {
            task.cancel()
        }
    }

    // MARK: - MCPTransport Protocol

    public var messages: AsyncThrowingStream<JSONRPCMessage, Error> {
        get throws {
            guard messageContinuation == nil else {
                throw TransportError.invalidState("Unsupported concurrent access to message stream")
            }
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: JSONRPCMessage.self)
            messageContinuation = continuation
            return stream
        }
    }

    public var stateMessages: AsyncStream<TransportState> {
        get throws {
            guard transportStateContinuation == nil else {
                throw TransportError.invalidState(
                    "Unsupported concurrent access to transport state")
            }
            let (stream, continuation) = AsyncStream.makeStream(of: TransportState.self)
            transportStateContinuation = continuation
            return stream
        }
    }

    public func start() async throws {
        guard state != .connected else {
            logger.warning("StreamableHTTPTransport start called but already connected.")
            throw TransportError.invalidState("Already connected")
        }

        state = .connecting

        // Start SSE stream
        let streamID = UUID()
        let streamTask = Task {
            try await self.startSSEStream()
        }
        activeStreams[streamID] = streamTask

        // Wait for connection
        while state == .connecting {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    public func stop() async {
        logger.debug("Stopping StreamableHTTPTransport")
        state = .disconnected
        await cleanup()
        logger.info("StreamableHTTPTransport disconnected")
    }

    public func send(_ message: JSONRPCMessage, timeout: TimeInterval? = nil) async throws {
        guard state == .connected else {
            throw TransportError.invalidState("Not connected")
        }

        try await withRetry(operation: "HTTP POST") {
            try await self.sendMessage(message, timeout: timeout)
        }
    }

    // MARK: - Private Methods

    private func cleanup() async {
        for task in activeStreams.values {
            task.cancel()
        }
        activeStreams.removeAll()

        messageContinuation?.finish()
        messageContinuation = nil

        transportStateContinuation?.finish()
        transportStateContinuation = nil

        sessionID = nil
        lastEventID = nil
        await parser.reset()
    }

    private func handleSSEEvent(_ event: SSEEvent) async throws {
        guard !event.data.isEmpty else { return }

        // Try to decode as single message first
        if let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: event.data) {
            logger.debug(
                "Decoded single message: \(String(data: event.data, encoding: .utf8) ?? "invalid")")
            messageContinuation?.yield(message)
        }
        // Try to decode as array of messages
        else if let messages = try? JSONDecoder().decode([JSONRPCMessage].self, from: event.data) {
            logger.debug(
                "Decoded message array: \(String(data: event.data, encoding: .utf8) ?? "invalid")")
            for message in messages {
                messageContinuation?.yield(message)
            }
        } else {
            logger.error(
                "Failed to decode message(s) from data: \(String(data: event.data, encoding: .utf8) ?? "invalid")"
            )
        }
    }

    private func startSSEStream() async throws {
        var request = URLRequest(url: httpConfig.endpoint)
        request.httpMethod = "GET"

        // Add headers
        for (key, value) in httpConfig.sseHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Add session ID if available
        if let sessionID = sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }

        // Add last event ID if available
        if let lastEventID = lastEventID {
            request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
        }

        let (bytes, response) = try await session.bytes(for: request, delegate: nil)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransportError.operationFailed("Invalid response type")
        }

        // Handle session ID
        if let newSessionID = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
            sessionID = newSessionID
            logger.debug("Received session ID: \(newSessionID)")
        }

        // Validate response
        switch httpResponse.statusCode {
        case 200:
            guard
                httpResponse.value(forHTTPHeaderField: "Content-Type")?.contains(
                    "text/event-stream") == true
            else {
                throw TransportError.operationFailed("Expected text/event-stream content type")
            }
        case 405:
            throw TransportError.operationFailed("Server does not support SSE")
        default:
            throw TransportError.operationFailed(
                "Unexpected status code: \(httpResponse.statusCode)")
        }

        state = .connected

        // Process SSE stream
        for try await line in bytes.lines {
            if let event = try await parser.parseLine(line) {
                try await handleSSEEvent(event)
            }
        }

        // Process any remaining data
        if let event = await parser.flush() {
            try await handleSSEEvent(event)
        }
    }

    private func sendMessage(_ message: JSONRPCMessage, timeout: TimeInterval?) async throws {
        var request = URLRequest(url: httpConfig.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout ?? configuration.sendTimeout

        // Add headers
        for (key, value) in httpConfig.defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Add session ID if available
        if let sessionID = sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }

        // Encode and validate message
        let messageData = try validate(message)
        request.httpBody = messageData

        let (data, response) = try await session.data(for: request, delegate: nil)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransportError.operationFailed("Invalid response type")
        }

        // Handle session expiration
        if httpResponse.statusCode == 404 {
            sessionID = nil
            throw TransportError.sessionExpired
        }

        // Handle response based on message type
        switch message {
        case .notification:
            guard httpResponse.statusCode == 202 else {
                throw TransportError.operationFailed("Expected 202 status code for notification")
            }

        case .response:
            guard httpResponse.statusCode == 202 else {
                throw TransportError.operationFailed("Expected 202 status code for response")
            }

        case .request:
            switch httpResponse.value(forHTTPHeaderField: "Content-Type") {
            case .some(let contentType) where contentType.contains("text/event-stream"):
                // Server will respond via SSE stream
                guard httpResponse.statusCode == 202 else {
                    throw TransportError.operationFailed(
                        "Expected 202 status code for SSE response")
                }

                // Process any SSE data in the response
                if !data.isEmpty {
                    let lines =
                        String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
                    for line in lines {
                        if let event = try await parser.parseLine(line) {
                            try await handleSSEEvent(event)
                        }
                    }
                }

            case .some(let contentType) where contentType.contains("application/json"):
                // Try to decode as single response
                if let response = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) {
                    messageContinuation?.yield(response)
                }
                // Try to decode as array of responses
                else if let responses = try? JSONDecoder().decode([JSONRPCMessage].self, from: data)
                {
                    for response in responses {
                        messageContinuation?.yield(response)
                    }
                } else {
                    throw TransportError.operationFailed("Invalid response format")
                }

            default:
                throw TransportError.operationFailed("Invalid content type for request response")
            }

        case .error:
            // Error responses should be handled like regular responses
            guard httpResponse.statusCode == 202 else {
                throw TransportError.operationFailed("Expected 202 status code for error response")
            }
        }
    }
}
