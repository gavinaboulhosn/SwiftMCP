import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "SSEClientTransport")

// MARK: - SSEClientTransport

extension SSETransportConfiguration {
  public static let dummyData = SSETransportConfiguration(
    sseURL: URL(string: "http://localhost:3000")!,
    postURL: nil,
    sseHeaders: ["some": "sse-value"],
    postHeaders: ["another": "post-value"],
    baseConfiguration: .dummyData)
}

/// Configuration settings for an SSE Transport option
public struct SSETransportConfiguration: Codable {

  // MARK: Lifecycle

  public init(
    sseURL: URL,
    postURL: URL? = nil,
    sseHeaders: [String: String] = [:],
    postHeaders: [String: String] = [:],
    baseConfiguration: TransportConfiguration = .default)
  {
    self.sseURL = sseURL
    self.postURL = postURL
    self.sseHeaders = sseHeaders
    self.postHeaders = postHeaders
    self.baseConfiguration = baseConfiguration
  }

  // MARK: Public

  public static let defaultSSEHeaders: [String: String] = [
    "Accept": "text/event-stream",
  ]
  public static let defaultPOSTHeaders: [String: String] = [
    "Content-Type": "application/json",
  ]

  public var sseURL: URL
  public var postURL: URL?
  public var sseHeaders: [String: String]
  public var postHeaders: [String: String]
  // TODO: does cookie / auth storage need to be on here too?
  public var baseConfiguration: TransportConfiguration

}

extension TransportConfiguration {
  public static let defaultSSE = TransportConfiguration(healthCheckEnabled: true, healthCheckInterval: 5.0)
}

/// A concrete implementation of `MCPTransport` providing Server-Sent Events (SSE) support.
///
/// This transport uses:
/// - An indefinite GET request to the SSE endpoint for receiving events.
/// - A short-lived POST for sending data, using an endpoint typically announced by the server via an SSE `endpoint` event.
/// It also supports retries via `RetryableTransport`.
public actor SSEClientTransport: MCPTransport, RetryableTransport {

  // MARK: Lifecycle

  /// Initialize an SSEClientTransport.
  ///
  /// - Parameters:
  ///   - configuration: The SSE Transport Configuration object. Required.
  public init(
    configuration: SSETransportConfiguration)
  {
    _configuration = configuration
    session = URLSession(configuration: .ephemeral)
    // TODO: revisit auth settings
    session.configuration.httpShouldSetCookies = true
    session.configuration.httpCookieStorage = .shared
    session.configuration.httpCookieAcceptPolicy = .always
    session.configuration.timeoutIntervalForRequest = configuration.baseConfiguration.requestTimeout
    session.configuration.timeoutIntervalForResource = configuration.baseConfiguration.responseTimeout
    session.configuration.waitsForConnectivity = configuration.baseConfiguration.connectTimeout > 0
    logger.debug("Initialized SSEClientTransport with sseURL=\(configuration.sseURL.absoluteString)")
  }

  public convenience init(
    sseURL: URL,
    postURL: URL? = nil,
    sseHeaders: [String: String] = [:],
    postHeaders: [String: String] = [:],
    baseConfiguration: TransportConfiguration = .defaultSSE)
  {
    let configuration = SSETransportConfiguration(
      sseURL: sseURL,
      postURL: postURL,
      sseHeaders: sseHeaders,
      postHeaders: postHeaders,
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

  /// SSE endpoint URL
  public var sseURL: URL { _configuration.sseURL }

  /// Optional post URL, typically discovered from an SSE `endpoint` event.
  /// When a new non‑nil URL is set, all waiting continuations are notified.
  public var postURL: URL? {
    get { _configuration.postURL }
    set {
      _configuration.postURL = newValue
      if let newURL = newValue {
        // Notify all waiting continuations of the new URL.
        for continuation in postURLContinuations {
          continuation.yield(newURL)
          continuation.finish()
        }
        postURLContinuations.removeAll()
      }
    }
  }

  /// Headers attached to SSE endpoint requests
  public var sseHeaders: [String: String] { _configuration.sseHeaders }
  /// Headers attached to POST endpoint requests
  public var postHeaders: [String: String] { _configuration.postHeaders }

  /// Provides a stream of inbound SSE messages as `JSONRPCMessage`.
  /// This call does not start the transport if it's not already started. The caller must `start()` first if needed.
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

  /// Starts the SSE connection by launching the read loop.
  public func start() async throws {
    guard state != .connected else {
      logger.warning("SSEClientTransport start called but already connected.")
      throw TransportError.invalidState("we are already connected, no need to call start")
    }
    state = .connecting

    let (ready, continuation) = AsyncStream.makeStream(of: Void.self)
    self.connectedContinuation = continuation

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
        // wait for the first task to complete and propagate any errors
        try await group.next()
        group.cancelAll()
      }
    }

    await ready
  }

  /// Stops the SSE connection, finishing the message stream and canceling tasks.
  public func stop() {
    logger.debug("Stopping SSEClientTransport.")
    state = .disconnected
    cleanup(nil)
    logger.info("SSEClientTransport is now disconnected.")
  }

  /// Sends data via a short-lived POST request.
  /// - Parameter message: The message to send (e.g. JSON-encoded).
  /// - Parameter timeout: Optional override for send timeout.
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

  // MARK: - RetryableTransport

  /// Retry a block of code with the configured `TransportRetryPolicy`.
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
    throw TransportError.operationFailed(
      "\(operation) failed after \(maxAttempts) attempts: \(String(describing: lastError))")
  }

  // MARK: Private

  private var _configuration: SSETransportConfiguration

  /// Session used for SSE streaming and short-lived POST
  private let session: URLSession
  /// Task that runs the indefinite SSE read loop
  private var sseReadTask: Task<Void, Error>?
  /// Continuation used by `messages()` for inbound SSE messages
  private var messageContinuation: AsyncThrowingStream<JSONRPCMessage, Error>.Continuation?
  /// Message listeners
  private var transportStateContinuation: AsyncStream<TransportState>.Continuation?
  /// Holds all continuations waiting for a POST URL to be resolved.
  private var postURLContinuations: [AsyncStream<URL>.Continuation] = []
  private var connectedContinuation: AsyncStream<Void>.Continuation?

  private func cleanup(_ error: Error?) {
    sseReadTask?.cancel()
    sseReadTask = nil
    messageContinuation?.finish(throwing: error)
    messageContinuation = nil
    connectedContinuation?.finish()
    connectedContinuation = nil
    transportStateContinuation?.finish()
    transportStateContinuation = nil

    // Finish and remove all waiting POST URL continuations.
    for continuation in postURLContinuations {
      continuation.finish()
    }
    postURLContinuations.removeAll()
  }

  // MARK: - SSE Read Loop

  /// Main SSE read loop, reading lines from the SSE endpoint and yielding them as needed.
  private func readLoop() async throws {
    let endpoint = sseURL
    do {
      var request = URLRequest(url: endpoint)
      request.timeoutInterval = configuration.connectTimeout
      for (k, v) in SSETransportConfiguration.defaultSSEHeaders {
        logger.info("setting \(k): \(v)")
        request.setValue(v, forHTTPHeaderField: k)
      }
      for (k, v) in sseHeaders {
        logger.info("setting \(k): \(v)")
        request.addValue(v, forHTTPHeaderField: k)
      }

      request.allHTTPHeaderFields?.forEach { key, value in
        logger.info("header: \(key): \(value ?? "nil")")
      }

      let (byteStream, response) = try await session.bytes(for: request)
      try validateHTTPResponse(response)

      // We have a good response!
      state = .connected
      connectedContinuation?.yield()
      connectedContinuation?.finish()

      // Accumulate lines into SSE events
      var dataBuffer = Data()
      var eventType = "message"
      var eventID: String?

      for try await line in byteStream.allLines {
        try Task.checkCancellation()

        if line.isEmpty {
          // End of an SSE event
          try await handleSSEEvent(type: eventType, id: eventID, data: dataBuffer)
          dataBuffer.removeAll()
          eventType = "message"
          eventID = nil
          continue
        } else if line.hasPrefix("event:") {
          eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
          continue
        } else if line.hasPrefix("data:") {
          let text = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
          if let chunk = text.data(using: .utf8) {
            dataBuffer.append(chunk)
          }
        } else if line.hasPrefix("id:") {
          eventID = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("retry:") {
          if let ms = parseRetry(line) {
            logger.debug("SSEClientTransport new retry policy in ms: \(ms)")
            _configuration.baseConfiguration.retryPolicy.baseDelay = TimeInterval(ms) / 1000.0
          }
        } else {
          logger.debug("SSEClientTransport ignoring unknown line: \(line)")
        }
      }

      // If there's leftover data in the buffer, handle it.
      if !dataBuffer.isEmpty {
        try await handleSSEEvent(type: eventType, id: eventID, data: dataBuffer)
      }
      logger.debug("SSE stream ended gracefully.")
      // Don't change to disconnected status, we are going to try to reconnect.
      return
    } catch is CancellationError {
      logger.debug("SSE read loop task cancelled.")
      // Don't change to disconnected status, we are going to try to reconnect.
      return
    } catch {
      logger.error("SSE read loop ended with error. \(error)")
      if
        let error = error as? NSError,
        error.domain == NSURLErrorDomain,
        error.code == NSURLErrorTimedOut
      {
        logger.warning("SSE connection closed / timed out. Will try to reconnect")
        return
      }
      throw error
    }
  }

  /// Parse and handle a single SSE event upon encountering a blank line.
  private func handleSSEEvent(type: String, id: String?, data: Data) async throws {
    logger.debug("SSE event id=\(id ?? ""), type=\(type), data=\(data).")
    guard data.count > 0 else {
      logger.debug("blank line passed to sse event handler")
      return
    }
    switch type {
    case "endpoint":
      try handleEndpointEvent(data)
    case "message":
      try handleMessage(data)
    default:
      logger.warning("UNHANDLED EVENT TYPE: \(type)")
      break
    }
  }

  private func handleMessage(_ data: Data) throws {
    logger.info("data: \(String(data: data, encoding: .utf8)!)")
    guard let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) else {
      throw TransportError.invalidMessage("Unable to parse JSONRPCMessage \(data)")
    }
    // TODO: add intercept for ping messages maybe?
    messageContinuation?.yield(message)
  }

  /// Validate that the SSE endpoint returned a successful 200 OK response.
  private func validateHTTPResponse(_ response: URLResponse) throws {
    guard
      let httpResp = response as? HTTPURLResponse,
      (200...299).contains(httpResp.statusCode)
    // TODO: validate "ok"
    else {
      // TODO: bubble up actual error
      throw TransportError.operationFailed("SSE request did not return HTTP 2XX.")
    }
  }

  /// If an SSE `endpoint` event is received, parse it as a new POST URL.
  private func handleEndpointEvent(_ data: Data) throws {
    guard
      let text = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !text.isEmpty
    else {
      throw TransportError.invalidMessage("Empty or invalid 'endpoint' SSE event.")
    }

    guard
      let baseURL = URL(string: "/", relativeTo: sseURL)?.baseURL,
      let newURL = URL(string: text, relativeTo: baseURL)
    else {
      throw TransportError.invalidMessage("Could not form absolute endpoint from: \(text)")
    }

    logger.debug("SSEClientTransport discovered POST endpoint: \(newURL.absoluteString)")
    postURL = newURL
  }

  /// Parse "retry: xyz" line, returning xyz as Int (milliseconds).
  private func parseRetry(_ line: String) -> Int? {
    let raw = line.dropFirst("retry:".count).trimmingCharacters(in: .whitespaces)
    return Int(raw)
  }

  // MARK: - POST Send
  /// Perform a short-lived POST request to send data.
  private func post(
    _ message: JSONRPCMessage,
    to url: URL,
    timeout: TimeInterval?)
    async throws
  {
    let messageData = try validate(message)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout ?? configuration.sendTimeout
    request.httpBody = messageData
    for (k, v) in SSETransportConfiguration.defaultPOSTHeaders {
      logger.info("setting \(k): \(v)")
      request.setValue(v, forHTTPHeaderField: k)
    }
    for (k, v) in postHeaders {
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
    logger.debug("SSEClientTransport POST send succeeded to \(url.absoluteString) with status code \(httpResponse.statusCode)")
    // Don't care about the result for now.
  }

  /// If postURL is not yet known, await it until the SSE server provides it or we time out.
  private func resolvePostURL(timeout: TimeInterval = 5) async throws -> URL {
    if let existing = postURL {
      return existing
    }
    let (stream, continuation) = AsyncStream.makeStream(of: URL.self)
    postURLContinuations.append(continuation)
    return try await withThrowingTimeout(seconds: timeout) {
      for try await url in stream {
        return url
      }
      throw TransportError.invalidState("URL never resolved")
    }
  }

  // MARK: - Timeout Helper

  /// Simple concurrency-based timeout wrapper for async operations.
  private func withThrowingTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping () async throws -> T)
    async throws -> T
  {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw TransportError.timeout(operation: "\(seconds)s elapsed")
      }
      let result = try await group.next()
      group.cancelAll()
      if let result {
        return result
      }
      throw TransportError.operationFailed("\(operation) returned nil result")
    }
  }
}

/// Extends `AsyncSequence` of bytes to produce lines for SSE processing.
extension AsyncSequence where Element == UInt8 {
  /// Splits an async byte stream into lines delimited by `\n`.
  var allLines: AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      Task {
        var buffer: [UInt8] = []
        var iterator = self.makeAsyncIterator()

        do {
          while let byte = try await iterator.next() {
            if byte == UInt8(ascii: "\n") {
              // End of line.
              if buffer.isEmpty {
                continuation.yield("") // blank line.
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
          // End of stream, flush partial.
          if !buffer.isEmpty {
            if let line = String(data: Data(buffer), encoding: .utf8) {
              continuation.yield(line)
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
}
