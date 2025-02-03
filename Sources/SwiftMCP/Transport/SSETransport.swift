import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "SSEClientTransport")

// MARK: - SSEClientTransport

extension SSETransportConfiguration {
  public static let dummyData = SSETransportConfiguration(
    sseURL: URL("http://localhost:3000")!,
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
    sseHeaders: [String: String] = SSETransportConfiguration.defaultSSEHeaders,
    postHeaders: [String: String] = SSETransportConfiguration.defaultPOSTHeaders,
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
  public static let defaultSSE = TransportConfiguration()
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

  // MARK: Public

  public private(set) var state = TransportState.disconnected

  public var configuration: TransportConfiguration {
    _configuration.baseConfiguration
  }

  /// SSE endpoint URL
  public var sseURL: URL { _configuration.sseURL }
  /// Optional post URL, typically discovered from an SSE `endpoint` event
  public var postURL: URL? { _configuration.postURL }

  /// Headers attached to SSE endpoint requests
  public var sseHeaders: [String: String] { _configuration.sseHeaders }
  /// Headers attached to POST endpoint requests
  public var postHeaders: [String: String] { _configuration.postHeaders }

  /// Provides a stream of inbound SSE messages as `Data`.
  /// This call does not start the transport if it's not already started. The caller must `start()` first if needed.
  public func messages() -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      Task { [weak self] in
        await self?.storeMessagesContinuation(continuation)
      }
    }
  }

  /// Starts the SSE connection by launching the read loop.
  public func start() async throws {
    guard state != .connected else {
      logger.info("SSEClientTransport start called but already connected.")
      return
    }

    logger.debug("SSEClientTransport is transitioning to .connecting")
    state = .connecting

    sseReadTask = Task {
      await runSSEReadLoop()
    }
  }

  /// Stops the SSE connection, finishing the message stream and canceling tasks.
  public func stop() {
    logger.debug("Stopping SSEClientTransport.")
    sseReadTask?.cancel()
    sseReadTask = nil

    messagesContinuation?.finish()
    messagesContinuation = nil

    // If we are waiting for postURL, fail it
    postURLWaitContinuation?.resume(throwing: CancellationError())
    postURLWaitContinuation = nil

    state = .disconnected
    logger.info("SSEClientTransport is now disconnected.")
  }

  /// Sends data via a short-lived POST request.
  /// - Parameter data: The data to send (e.g. JSON-encoded).
  /// - Parameter timeout: Optional override for send timeout.
  public func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
    logger.debug("Sending data via SSEClientTransport POST...")
    let targetURL = try await resolvePostURL(timeout: timeout)

    try await withRetry(operation: "SSE POST send") {
      try await self.performPOSTSend(data, to: targetURL, timeout: timeout)
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
  private var sseReadTask: Task<Void, Never>?

  /// Continuation used by `messages()` for inbound SSE messages
  private var messagesContinuation: AsyncThrowingStream<Data, Error>.Continuation?

  /// A single continuation used to await `postURL` if we haven't discovered it yet
  private var postURLWaitContinuation: CheckedContinuation<URL, Error>?

  /// Internally store the messages continuation inside the actor.
  private func storeMessagesContinuation(_ cont: AsyncThrowingStream<Data, Error>.Continuation) {
    messagesContinuation = cont
    cont.onTermination = { _ in
      Task { [weak self] in
        await self?.handleMessagesStreamTerminated()
      }
    }
  }

  /// Called when the consumer of `messages()` cancels their stream.
  private func handleMessagesStreamTerminated() {
    // Must remain on actor
    logger.debug("Messages stream terminated by consumer. Stopping SSE transport.")
    stop()
  }

  // MARK: - SSE Read Loop

  /// Main SSE read loop, reading lines from the SSE endpoint and yielding them as needed.
  private func runSSEReadLoop() async {
    let endpoint = sseURL
    do {
      var request = URLRequest(url: endpoint)
      request.timeoutInterval = configuration.connectTimeout
      for (k, v) in sseHeaders {
        request.addValue(v, forHTTPHeaderField: k)
      }

      let (byteStream, response) = try await session.bytes(for: request)
      try validateHTTPResponse(response)

      state = .connected
      logger.info(
        "SSEClientTransport connected to \(endpoint.absoluteString, privacy: .private).")

      // Accumulate lines into SSE events
      var dataBuffer = Data()
      var eventType = "message"
      var eventID: String?

      for try await line in byteStream.allLines {
        guard !Task.isCancelled else { break }

        if line.isEmpty {
          // End of an SSE event
          try await handleSSEEvent(type: eventType, id: eventID, data: dataBuffer)
          dataBuffer.removeAll()
          eventType = "message"
          eventID = nil
        } else if line.hasPrefix("event:") {
          eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
          let text = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
          if let chunk = text.data(using: .utf8) {
            dataBuffer.append(chunk)
          }
        } else if line.hasPrefix("id:") {
          eventID = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("retry:") {
          if let ms = parseRetry(line) {
            _configuration.baseConfiguration.retryPolicy.baseDelay = TimeInterval(ms) / 1000.0
          }
        } else {
          logger.debug("SSEClientTransport ignoring unknown line: \(line)")
        }
      }

      // If there's leftover data in the buffer, handle it
      if !dataBuffer.isEmpty {
        try await handleSSEEvent(type: eventType, id: eventID, data: dataBuffer)
      }

      // SSE stream ended gracefully
      messagesContinuation?.finish()
      state = .disconnected
      logger.debug("SSE stream ended gracefully.")
    } catch is CancellationError {
      logger.debug("SSE read loop cancelled.")
      state = .disconnected
      messagesContinuation?.finish()
    } catch {
      logger.error("SSE read loop failed with error: \(error.localizedDescription)")
      state = .failed(error)
      messagesContinuation?.finish(throwing: error)
    }
  }

  /// Parse and handle a single SSE event upon encountering a blank line.
  private func handleSSEEvent(type: String, id _: String?, data: Data) async throws {
    logger.debug("SSE event type=\(type), size=\(data.count) bytes.")
    switch type {
    case "message":
      messagesContinuation?.yield(data)
    case "endpoint":
      try handleEndpointEvent(data)
    default:
      messagesContinuation?.yield(data)
    }
  }

  /// Validate that the SSE endpoint returned a successful 200 OK response.
  private func validateHTTPResponse(_ response: URLResponse) throws {
    guard
      let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200
    else {
      throw TransportError.operationFailed("SSE request did not return HTTP 200.")
    }
  }

  /// If SSE `endpoint` event is received, parse it as a new POST URL.
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
    _configuration.postURL = newURL

    // If someone was awaiting postURL, resume them
    postURLWaitContinuation?.resume(returning: newURL)
    postURLWaitContinuation = nil
  }

  /// Parse "retry: xyz" line, returning xyz as Int (milliseconds).
  private func parseRetry(_ line: String) -> Int? {
    let raw = line.dropFirst("retry:".count).trimmingCharacters(in: .whitespaces)
    return Int(raw)
  }

  // MARK: - POST Send

  /// Perform a short-lived POST request to send data.
  private func performPOSTSend(
    _ data: Data,
    to url: URL,
    timeout: TimeInterval?)
    async throws
  {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout ?? configuration.sendTimeout
    request.httpBody = data
    for (k, v) in postHeaders {
      request.setValue(v, forHTTPHeaderField: k)
    }

    let (_, response) = try await session.data(for: request)
    guard
      let httpResp = response as? HTTPURLResponse,
      (200...299).contains(httpResp.statusCode)
    else {
      throw TransportError.operationFailed("POST request to \(url) failed with non-2xx response.")
    }
    logger.debug("SSEClientTransport POST send succeeded.")
  }

  /// If postURL is not yet known, await it until SSE server provides it or we time out.
  private func resolvePostURL(timeout: TimeInterval?) async throws -> URL {
    if let existing = postURL {
      logger.debug("Using existing postURL: \(existing.absoluteString)")
      return existing
    }

    let effectiveTimeout = timeout ?? configuration.sendTimeout
    // Wait for the SSE 'endpoint' event to supply postURL
    return try await withThrowingTimeout(seconds: effectiveTimeout) {
      try await withCheckedThrowingContinuation { continuation in
        self.postURLWaitContinuation = continuation
      }
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
      let result = try await group.next()!
      group.cancelAll()
      return result
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
              // End of line
              if buffer.isEmpty {
                continuation.yield("") // blank line
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
          // End of stream, flush partial
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
