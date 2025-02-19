import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "SSEClientTransport")

extension SSETransportConfiguration {
  public static let dummyData = SSETransportConfiguration(
    sseURL: URL(string: "http://localhost:3000")!,
    postURL: nil,
    sseHeaders: ["some": "sse-value"],
    baseConfiguration: .dummyData)
}

/// Configuration settings for an SSE Transport option
public struct SSETransportConfiguration: Codable {

  // MARK: Lifecycle

  public init(
    sseURL: URL,
    postURL: URL? = nil,
    sseHeaders: [String: String] = [:],
    baseConfiguration: TransportConfiguration = .default)
  {
    self.sseURL = sseURL
    self.postURL = postURL
    self.sseHeaders = sseHeaders
    self.baseConfiguration = baseConfiguration
  }

  // MARK: Public

  public static let defaultSSEHeaders: [String: String] = [
    "Accept": "text/event-stream",
  ]
  public var sseURL: URL
  public var postURL: URL?
  public var sseHeaders: [String: String]
  public var baseConfiguration: TransportConfiguration

}

extension TransportConfiguration {
  public static let defaultSSE = TransportConfiguration(healthCheckEnabled: true, healthCheckInterval: 5.0)
}

public actor SSEClientTransport: MCPTransport, RetryableTransport {

  // MARK: Lifecycle

  public init(configuration: SSETransportConfiguration) {
    _configuration = configuration
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = true
    config.httpCookieStorage = .shared
    config.httpCookieAcceptPolicy = .always
    config.timeoutIntervalForRequest = configuration.baseConfiguration.requestTimeout
    config.timeoutIntervalForResource = configuration.baseConfiguration.responseTimeout
    config.waitsForConnectivity = true
    session = URLSession(configuration: config)
    logger.debug("Initialized SSEClientTransport with sseURL=\(configuration.sseURL.absoluteString)")
  }

  public convenience init(
    sseURL: URL,
    postURL: URL? = nil,
    sseHeaders: [String: String] = [:],
    baseConfiguration: TransportConfiguration = .defaultSSE)
  {
    let configuration = SSETransportConfiguration(
      sseURL: sseURL,
      postURL: postURL,
      sseHeaders: sseHeaders,
      baseConfiguration: baseConfiguration)
    self.init(configuration: configuration)
  }

  deinit {
    cleanup(nil)
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
        throw TransportError.invalidState("Unsupported concurrent access to transport state")
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
    let (ready, continuation) = AsyncStream.makeStream(of: Void.self)
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
    await ready
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
    block: @escaping () async throws -> T)
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
        logger.warning("\(operation) failed (attempt \(attempt)). Retrying in \(delay) seconds.")
        try await Task.sleep(for: .seconds(delay))
        attempt += 1
      }
    }
    throw TransportError.operationFailed("\(operation) failed after \(maxAttempts) attempts: \(String(describing: lastError))")
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

  private func cleanup(_ error: Error?) {
    sseReadTask?.cancel()
    sseReadTask = nil
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
            logger.info("Final header: \(key): \(value ?? "nil")")
          }
        }
        
        let (byteStream, response) = try await session.bytes(for: request)
        try validateHTTPResponse(response)

        var dataBuffer = Data()
        var eventType = "message"
        var eventID: String?

        for try await line in byteStream.allLines {
          // Trim whitespace and newlines from the line
          let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
          print("SSE line: \(trimmedLine)")
          try Task.checkCancellation()
          
          // If the trimmed line is empty, then it marks the end of an event.
          if trimmedLine.isEmpty {
            if !dataBuffer.isEmpty {
              print("Processing event: type=\(eventType), data=\(String(data: dataBuffer, encoding: .utf8) ?? "invalid utf8")")
              try await handleSSEEvent(type: eventType, id: eventID, data: dataBuffer)
              dataBuffer.removeAll()
              eventType = "message" // Reset to default
              eventID = nil
            } else {
              print("Empty line received but data buffer is empty")
            }
            continue
          }
          
          // Check for comment lines (starting with a colon)
          if trimmedLine.hasPrefix(":") {
            continue
          }
          
          // Parse field
          if trimmedLine.hasPrefix("event:") {
            eventType = String(trimmedLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            print("Event type set to: \(eventType)")
          } else if trimmedLine.hasPrefix("data:") {
            let text = String(trimmedLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if let chunk = (text + "\n").data(using: .utf8) {
              dataBuffer.append(chunk)
              print("Data buffer now contains: \(String(data: dataBuffer, encoding: .utf8) ?? "invalid utf8")")
            }
          } else if trimmedLine.hasPrefix("id:") {
            eventID = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
          } else if trimmedLine.hasPrefix("retry:") {
            if let ms = Int(String(trimmedLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)) {
              logger.debug("Updating retry policy delay to \(ms) ms")
              _configuration.baseConfiguration.retryPolicy.baseDelay = TimeInterval(ms) / 1000.0
            }
          } else {
            logger.debug("Ignoring unknown SSE line: \(trimmedLine)")
          }
        }

        // Process any remaining data
        if !dataBuffer.isEmpty {
          try await handleSSEEvent(type: eventType, id: eventID, data: dataBuffer)
        }

        logger.debug("SSE stream ended for URL \(endpoint.absoluteString), attempting immediate reconnection")
        state = .connecting
        try await Task.sleep(for: .milliseconds(100))
        continue

      } catch is CancellationError {
        logger.debug("SSE read loop cancelled for URL \(endpoint.absoluteString)")
        throw TransportError.connectionFailed("SSE read loop cancelled")
      } catch {
        if let nsError = error as NSError? {
          logger.error(
            "Error in SSE read loop for URL \(endpoint.absoluteString): Domain=\(nsError.domain) Code=\(nsError.code) \(nsError.localizedDescription)")
          
          if nsError.domain == NSURLErrorDomain &&
             (nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorNetworkConnectionLost) {
            state = .connecting
            try await Task.sleep(for: .milliseconds(100))
            continue
          } else {
            state = .disconnected
            cleanup(error)
            throw error
          }
        } else {
          logger.error("Fatal error in SSE read loop for URL \(endpoint.absoluteString): \(error.localizedDescription)")
          state = .disconnected
          cleanup(error)
          throw error
        }
      }
    }
  }
  
  private func handleSSEEvent(type: String, id: String?, data: Data) async throws {
    // Trim any whitespace or newlines from the event type
    let cleanType = type.trimmingCharacters(in: .whitespacesAndNewlines)
    
    logger.debug("SSE event id=\(id ?? ""), type=\(cleanType), data=\(data.count) bytes.")
    guard data.count > 0 else {
      logger.debug("blank line passed to sse event handler")
      return
    }

    // Log the raw event data for debugging
    if let rawData = String(data: data, encoding: .utf8) {
      logger.debug("Raw event data: \(rawData)")
    }

    switch cleanType {
    case "endpoint":
      logger.debug("Processing endpoint event...")
      try handleEndpointEvent(data)
      logger.debug("Endpoint event processed successfully")
    case "message":
      try handleMessage(data)
    case "ping":
      // Keep the connection alive by sending a GET request
      Task {
        do {
          var request = URLRequest(url: sseURL)
          request.timeoutInterval = 5 // Short timeout for ping
          request.httpMethod = "GET"
          request.setValue("application/json", forHTTPHeaderField: "Accept")
          for (key, value) in sseHeaders {
            request.setValue(value, forHTTPHeaderField: key)
          }
            logger.debug("Sending ping response to \(self.sseURL.absoluteString)")
          let (_, response) = try await session.data(for: request)
          if let httpResponse = response as? HTTPURLResponse {
            logger.debug("Ping response received with status: \(httpResponse.statusCode)")
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
      throw TransportError.operationFailed("SSE request did not return HTTP 2XX. Response: \(response)")
    }
  }

  private func handleEndpointEvent(_ data: Data) throws {
    let rawText = String(data: data, encoding: .utf8) ?? "invalid utf8"
    print("Raw endpoint data: '\(rawText)'")
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      logger.error("Empty or invalid 'endpoint' SSE event data")
      throw TransportError.invalidMessage("Empty or invalid 'endpoint' SSE event.")
    }

    logger.debug("Parsing endpoint URL from: \(text)")
    print("SSE URL: \(sseURL.absoluteString)")
    
    // Use the SSE URL as the base URL
    let baseURL = sseURL
    print("Using base URL: '\(baseURL.absoluteString)'")
    
    // Ensure the endpoint path starts with /
    let endpointPath = text.hasPrefix("/") ? text : "/" + text
    print("Endpoint path: '\(endpointPath)'")
    
    // Resolve the endpoint path against the base URL
    guard let endpointURL = URL(string: endpointPath, relativeTo: baseURL)?.absoluteURL else {
      logger.error("Failed to parse endpoint URL from: \(text)")
      throw TransportError.invalidMessage("Could not parse endpoint URL from: \(text)")
    }
    
    logger.debug("Resolved endpoint URL: \(endpointURL.absoluteString)")
    guard endpointURL.scheme == baseURL.scheme else {
      logger.error("Endpoint URL scheme mismatch: \(endpointURL.scheme ?? "nil") != \(baseURL.scheme ?? "nil")")
      throw TransportError.invalidMessage("Endpoint URL scheme mismatch")
    }
    
    print("Final endpoint URL: '\(endpointURL.absoluteString)'")
    
    // Update the POST endpoint
    if postURL != nil {
        logger.debug("Replacing existing endpoint URL \(self.postURL!.absoluteString) with new URL \(endpointURL.absoluteString)")
    }
    
    logger.debug("SSEClientTransport discovered POST endpoint: \(endpointURL.absoluteString)")
    postURL = endpointURL
    
    // First endpoint event means we're ready to start sending messages
    state = .connected
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

  private func parseRetry(_ line: String) -> Int? {
    let raw = line.dropFirst("retry:".count).trimmingCharacters(in: .whitespaces)
    return Int(raw)
  }

  private func post(
    _ message: JSONRPCMessage,
    to url: URL,
    timeout: TimeInterval?)
    async throws
  {
    guard let targetURL = postURL else {
      // Queue the request if we don't have a POST endpoint yet
      pendingRequests.append(message)
      throw TransportError.invalidState("No POST endpoint available, request queued for retry")
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
      logger.info("header: \(key): \(value ?? "nil")")
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
    logger.debug("SSEClientTransport POST send succeeded to \(targetURL.absoluteString) with status code \(httpResponse.statusCode)")
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

extension AsyncSequence where Element == UInt8 {
  var allLines: AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      Task {
        var buffer: [UInt8] = []
        var iterator = self.makeAsyncIterator()
        do {
          while let byte = try await iterator.next() {
            if byte == UInt8(ascii: "\n") {
              if buffer.isEmpty {
                continuation.yield("")
              } else {
                if let line = String(data: Data(buffer), encoding: .utf8) {
                  continuation.yield(line)
                } else {
                  throw TransportError.invalidMessage("Could not decode SSE line as UTF-8.")
                }
                buffer.removeAll()
              }
            } else {
              buffer.append(byte)
            }
          }
          if !buffer.isEmpty, let line = String(data: Data(buffer), encoding: .utf8) {
            continuation.yield(line)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
}
