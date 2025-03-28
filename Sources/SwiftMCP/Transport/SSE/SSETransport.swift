import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "SSEClientTransport")

// MARK: - SSEClientTransport

public actor SSEClientTransport: MCPTransport, RetryableTransport {
    // MARK: Lifecycle

    public init(configuration: SSETransportConfiguration) {
        _configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = true
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 300  // 5 minutes
        config.timeoutIntervalForResource = 3600  // 1 hour
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
        logger.debug(
            "Initialized SSEClientTransport with sseURL=\(configuration.sseURL.absoluteString)")
    }

    public init(
        sseURL: URL,
        postURL: URL? = nil,
        sseHeaders: [String: String] = [:],
        baseConfiguration: TransportConfiguration = .defaultSSE
    ) {
        let config = SSETransportConfiguration(
            sseURL: sseURL,
            postURL: postURL,
            sseHeaders: sseHeaders,
            baseConfiguration: baseConfiguration)
        self.init(configuration: config)
    }

    deinit {
        // For Swift 6 compatibility, we cancel tasks directly without capturing self
        sseReadTask?.cancel()
        keepAliveTask?.cancel()
        // Other cleanup will happen automatically as the object is deallocated
    }

    // MARK: Public

    public private(set) var state = TransportState.disconnected {
        didSet {
            let newState = state
            logger.info("client state update: \(oldValue) -> \(newState)")
            transportStateContinuation?.yield(with: .success(newState))
        }
    }

    public var configuration: TransportConfiguration {
        _configuration.baseConfiguration
    }

    public var sseURL: URL { _configuration.sseURL }
    public var postURL: URL? {
        get { _configuration.postURL }
        set {
            _configuration.postURL = newValue
            if let newURL = newValue {
                for continuation in postURLContinuations {
                    continuation.yield(newURL)
                    continuation.finish()
                }
                postURLContinuations.removeAll()
            }
        }
    }

    public var sseHeaders: [String: String] { _configuration.sseHeaders }

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
            logger.warning("SSEClientTransport start called but already connected.")
            throw TransportError.invalidState("Already connected, no need to call start")
        }
        state = .connecting
        let (_, continuation) = AsyncStream.makeStream(of: Void.self)
        connectedContinuation = continuation
        sseReadTask = Task<Void, Error> {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    while true {
                        try Task.checkCancellation()
                        try await self.readLoop()
                    }
                }
                group.addTask {
                    while true {
                        try Task.checkCancellation()
                        try await self.startHealthCheckTask()
                    }
                }
                try await group.next()
                group.cancelAll()
            }
        }
        // Wait for the connection to be established
        while state == .connecting {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    public func stop() {
        logger.debug("Stopping SSEClientTransport.")
        state = .disconnected
        cleanup(nil)
        logger.info("SSEClientTransport is now disconnected.")
    }

    public func send(_ message: JSONRPCMessage, timeout: TimeInterval? = nil) async throws {
        guard state == .connected else {
            throw TransportError.invalidState("Not connected")
        }
        logger.debug("Sending data via SSEClientTransport POST...")
        let targetURL: URL
        if let postURL {
            targetURL = postURL
        } else {
            targetURL = try await resolvePostURL()
        }
        try await withRetry(operation: "SSE POST send") {
            try await self.post(message, to: targetURL, timeout: timeout)
        }
    }

    public func withRetry<T>(
        operation: String,
        block: @escaping () async throws -> T
    )
        async throws -> T
    {
        var attempt = 1
        let maxAttempts = configuration.retryPolicy.maxAttempts
        var lastError: Error?
        while attempt <= maxAttempts {
            do {
                return try await block()
            } catch {
                lastError = error
                guard attempt < maxAttempts else { break }
                let delay = configuration.retryPolicy.delay(forAttempt: attempt)
                logger.warning(
                    "\(operation) failed (attempt \(attempt)). Retrying in \(delay) seconds.")
                try await Task.sleep(for: .seconds(delay))
                attempt += 1
            }
        }
        throw TransportError.operationFailed(
            "\(operation) failed after \(maxAttempts) attempts: \(String(describing: lastError))")
    }

    // MARK: Private

    private var _configuration: SSETransportConfiguration
    private let session: URLSession
    private var sseReadTask: Task<Void, Error>?
    private var messageContinuation: AsyncThrowingStream<JSONRPCMessage, Error>.Continuation?
    private var transportStateContinuation: AsyncStream<TransportState>.Continuation?
    private var postURLContinuations: [AsyncStream<URL>.Continuation] = []
    private var connectedContinuation: AsyncStream<Void>.Continuation?
    private var pendingRequests: [JSONRPCMessage] = []
    private var keepAliveTask: Task<Void, Error>?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 10  // Maximum number of reconnection attempts
    private let parser = SSEParser()

    private func cleanup(_ error: Error?) {
        sseReadTask?.cancel()
        sseReadTask = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil
        messageContinuation?.finish(throwing: error)
        messageContinuation = nil
        connectedContinuation?.finish()
        connectedContinuation = nil
        transportStateContinuation?.finish()
        transportStateContinuation = nil
        for continuation in postURLContinuations {
            continuation.finish()
        }
        postURLContinuations.removeAll()
    }

    private func readLoop() async throws {
        let endpoint = sseURL
        while true {
            do {
                // Cancel any existing keep-alive task
                keepAliveTask?.cancel()
                keepAliveTask = nil

                var request = URLRequest(url: endpoint)
                request.timeoutInterval = configuration.connectTimeout

                for (key, value) in SSETransportConfiguration.defaultSSEHeaders {
                    logger.info("Setting default SSE header: \(key): \(value)")
                    request.setValue(value, forHTTPHeaderField: key)
                }

                for (key, value) in sseHeaders {
                    logger.info("Setting SSE header: \(key): \(value)")
                    request.addValue(value, forHTTPHeaderField: key)
                }

                if let headers = request.allHTTPHeaderFields {
                    for (key, value) in headers {
                        logger.info("Final header: \(key): \(value)")
                    }
                }

                // Start new keep-alive task only after successful connection
                let (byteStream, response) = try await session.bytes(for: request)
                try validateHTTPResponse(response)

                // Connection successful, start keep-alive
                keepAliveTask = Task {
                    do {
                        while true {
                            try await Task.sleep(for: .seconds(25))
                            if let data = ": keepalive\n\n".data(using: .utf8) {
                                logger.debug("Sending keep-alive message")
                                // Process the keep-alive as a normal SSE message
                                try await handleSSEEvent(SSEEvent(data: data))
                            }
                        }
                    } catch {
                        logger.debug("Keep-alive task cancelled: \(error.localizedDescription)")
                    }
                }

                for try await line in byteStream.allLines {
                    try Task.checkCancellation()
                    if let event = try await parser.parseLine(line) {
                        try await handleSSEEvent(event)
                    }
                }

                // Process any remaining data
                if let event = await parser.flush() {
                    try await handleSSEEvent(event)
                }

                logger.debug(
                    "SSE stream ended for URL \(endpoint.absoluteString), attempting immediate reconnection"
                )
                state = .connecting
                try await Task.sleep(for: .milliseconds(100))
                continue

            } catch is CancellationError {
                logger.debug("SSE read loop cancelled for URL \(endpoint.absoluteString)")
                throw TransportError.connectionFailed("SSE read loop cancelled")
            } catch {
                if let nsError = error as NSError? {
                    logger.error(
                        "Error in SSE read loop for URL \(endpoint.absoluteString): Domain=\(nsError.domain) Code=\(nsError.code) \(nsError.localizedDescription)"
                    )

                    if nsError.domain == NSURLErrorDomain {
                        let isRecoverable =
                            nsError.code == NSURLErrorCancelled
                            || nsError.code == NSURLErrorTimedOut
                            || nsError.code == NSURLErrorNetworkConnectionLost

                        if isRecoverable {
                            switch nsError.code {
                            case NSURLErrorCancelled:
                                logger.info("Connection cancelled, attempting reconnection...")
                            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost:
                                logger.info(
                                    "Connection lost or timed out, attempting reconnection...")
                            default:
                                break  // Should never happen due to isRecoverable check
                            }

                            // Try to reconnect
                            if try await attemptReconnection() {
                                continue
                            }
                        }

                        // If not recoverable or reconnection failed
                        state = .disconnected
                        cleanup(error)
                        throw error
                    } else {
                        state = .disconnected
                        cleanup(error)
                        throw error
                    }
                } else {
                    logger.error(
                        "Fatal error in SSE read loop for URL \(endpoint.absoluteString): \(error.localizedDescription)"
                    )
                    state = .disconnected
                    cleanup(error)
                    throw error
                }
            }
        }
    }

    private func handleSSEEvent(_ event: SSEEvent) async throws {
        // Trim any whitespace or newlines from the event type
        let cleanType = event.type.trimmingCharacters(in: .whitespacesAndNewlines)

        logger.debug(
            "SSE event id=\(event.id ?? ""), type=\(cleanType), data=\(event.data.count) bytes.")
        guard event.data.count > 0 else {
            logger.debug("blank line passed to sse event handler")
            return
        }

        // Log the raw event data for debugging
        if let rawData = String(data: event.data, encoding: .utf8) {
            logger.debug("Raw event data: \(rawData)")
        }

        switch cleanType {
        case "endpoint":
            logger.debug("Processing endpoint event...")
            try handleEndpointEvent(event.data)
            logger.debug("Endpoint event processed successfully")

        case "message":
            try handleMessage(event.data)

        case "ping":
            // Keep the connection alive by sending a GET request
            Task {
                do {
                    var request = URLRequest(url: sseURL)
                    request.timeoutInterval = 5  // Short timeout for ping
                    request.httpMethod = "GET"
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    for (key, value) in sseHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                    logger.debug("Sending ping response to \(self.sseURL.absoluteString)")
                    let (_, response) = try await session.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse {
                        logger.debug(
                            "Ping response received with status: \(httpResponse.statusCode)")
                    }
                } catch {
                    logger.error("Failed to send ping response: \(error.localizedDescription)")
                }
            }

        case "":
            logger.debug("Received empty event type, ignoring")

        default:
            logger.warning("UNHANDLED EVENT TYPE: \(cleanType)")
        }
    }

    private func handleMessage(_ data: Data) throws {
        logger.info("data: \(String(data: data, encoding: .utf8)!)")
        guard let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) else {
            throw TransportError.invalidMessage("Unable to parse JSONRPCMessage \(data)")
        }
        messageContinuation?.yield(message)
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard
            let httpResp = response as? HTTPURLResponse,
            (200...299).contains(httpResp.statusCode)
        else {
            throw TransportError.operationFailed(
                "SSE request did not return HTTP 2XX. Response: \(response)")
        }
    }

    private func handleEndpointEvent(_ data: Data) throws {
        let rawText = String(data: data, encoding: .utf8) ?? "invalid utf8"
        logger.debug("Raw endpoint data: '\(rawText)'")
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            logger.error("Empty or invalid 'endpoint' SSE event data")
            throw TransportError.invalidMessage("Empty or invalid 'endpoint' SSE event.")
        }

        logger.debug("Parsing endpoint URL from: \(text)")
        logger.debug("SSE URL: \(self.sseURL.absoluteString)")

        // Use the SSE URL as the base URL
        let baseURL = sseURL
        logger.debug("Using base URL: '\(baseURL.absoluteString)'")

        // Ensure the endpoint path starts with /
        let endpointPath = text.hasPrefix("/") ? text : "/" + text
        logger.debug("Endpoint path: '\(endpointPath)'")

        // Resolve the endpoint path against the base URL
        guard let endpointURL = URL(string: endpointPath, relativeTo: baseURL)?.absoluteURL else {
            logger.error("Failed to parse endpoint URL from: \(text)")
            throw TransportError.invalidMessage("Could not parse endpoint URL from: \(text)")
        }

        logger.debug("Resolved endpoint URL: \(endpointURL.absoluteString)")
        guard endpointURL.scheme == baseURL.scheme else {
            logger.error(
                "Endpoint URL scheme mismatch: \(endpointURL.scheme ?? "nil") != \(baseURL.scheme ?? "nil")"
            )
            throw TransportError.invalidMessage("Endpoint URL scheme mismatch")
        }

        logger.debug("Final endpoint URL: '\(endpointURL.absoluteString)'")

        // Update the POST endpoint
        if postURL != nil {
            logger.debug(
                "Replacing existing endpoint URL \(self.postURL!.absoluteString) with new URL \(endpointURL.absoluteString)"
            )
        }

        logger.debug("SSEClientTransport discovered POST endpoint: \(endpointURL.absoluteString)")
        postURL = endpointURL

        // First endpoint event means we're ready to start sending messages
        state = .connected
        reconnectAttempt = 0  // Reset reconnection counter on successful connection
        connectedContinuation?.yield()
        connectedContinuation?.finish()

        // Retry any pending requests with new endpoint
        for message in pendingRequests {
            Task {
                try? await send(message)
            }
        }
        pendingRequests.removeAll()
    }

    private func attemptReconnection() async throws -> Bool {
        if reconnectAttempt < maxReconnectAttempts {
            reconnectAttempt += 1
            let delay = TimeInterval(pow(2.0, Double(reconnectAttempt - 1)))  // Exponential backoff
            logger.info(
                "Reconnection attempt \(self.reconnectAttempt)/\(self.maxReconnectAttempts) in \(delay) seconds"
            )
            state = .connecting
            try await Task.sleep(for: .seconds(delay))
            return true
        } else {
            logger.error("Maximum reconnection attempts (\(self.maxReconnectAttempts)) reached")
            return false
        }
    }

    private func post(
        _ message: JSONRPCMessage,
        to _: URL,
        timeout: TimeInterval?
    )
        async throws
    {
        guard let targetURL = postURL else {
            // Queue the request if we don't have a POST endpoint yet
            pendingRequests.append(message)
            throw TransportError.invalidState(
                "No POST endpoint available, request queued for retry")
        }

        let messageData = try validate(message)
        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout ?? configuration.sendTimeout
        request.httpBody = messageData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in sseHeaders {
            logger.info("setting \(k): \(v)")
            request.setValue(v, forHTTPHeaderField: k)
        }
        logger.info("POST request: \(String(data: messageData, encoding: .utf8)!)")
        request.allHTTPHeaderFields?.forEach { key, value in
            logger.info("header: \(key): \(value)")
        }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransportError.operationFailed("Invalid response type received")
        }
        if let responseString = String(data: data, encoding: .utf8) {
            logger.debug("Response data: \(responseString)")
        } else {
            logger.debug("Received non-text response of \(data.count) bytes")
        }
        try validateHTTPResponse(httpResponse)
        logger.debug(
            "SSEClientTransport POST send succeeded to \(targetURL.absoluteString) with status code \(httpResponse.statusCode)"
        )
    }

    private func resolvePostURL(timeout: TimeInterval = 25) async throws -> URL {
        // Wait for a valid postURL
        let endTime = Date().addingTimeInterval(timeout)
        while postURL == nil {
            guard Date() < endTime else {
                throw TransportError.timeout(operation: "Waiting for endpoint URL")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        return postURL!
    }
}
