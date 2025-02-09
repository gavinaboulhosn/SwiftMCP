import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "SSEClientTransport")

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
  public var baseConfiguration: TransportConfiguration

}

extension TransportConfiguration {
  public static let defaultSSE = TransportConfiguration(healthCheckEnabled: true, healthCheckInterval: 5.0)
}

public actor SSEClientTransport: MCPTransport, RetryableTransport {

  // MARK: Lifecycle

  public init(configuration: SSETransportConfiguration) {
    _configuration = configuration
    session = URLSession(configuration: .ephemeral)
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
  public var postHeaders: [String: String] { _configuration.postHeaders }

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
      state = .connected
      connectedContinuation?.yield()
      connectedContinuation?.finish()

      var dataBuffer = Data()
      var eventType = "message"
      var eventID: String?

      for try await line in byteStream.allLines {
        try Task.checkCancellation()
        if line.isEmpty {
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
            logger.debug("Updating retry policy delay to \(ms) ms")
            _configuration.baseConfiguration.retryPolicy.baseDelay = TimeInterval(ms) / 1000.0
          }
        } else {
          logger.debug("Ignoring unknown SSE line: \(line)")
        }
      }

      if !dataBuffer.isEmpty {
        try await handleSSEEvent(type: eventType, id: eventID, data: dataBuffer)
      }

      logger.debug("SSE stream ended gracefully for URL \(endpoint.absoluteString)")
      cleanup(nil)
      throw TransportError.connectionFailed("SSE stream ended gracefully, triggering reconnection.")

    } catch is CancellationError {
      logger.debug("SSE read loop cancelled for URL \(endpoint.absoluteString)")
    } catch {
      let urlString = endpoint.absoluteString
      if let nsError = error as NSError? {
        logger
          .error(
            "Error in SSE read loop for URL \(urlString): Domain=\(nsError.domain) Code=\(nsError.code) \(nsError.localizedDescription)")
        if
          nsError.domain == NSURLErrorDomain &&
          (nsError.code == NSURLErrorTimedOut || nsError.code == NSURLErrorNetworkConnectionLost)
        {
          state = .disconnected
          cleanup(error)
          throw TransportError.connectionFailed("SSE connection lost or timed out, triggering immediate reconnection.")
        } else {
          state = .disconnected
          cleanup(error)
          throw error
        }
      } else {
        logger.error("Fatal error in SSE read loop for URL \(urlString): \(error.localizedDescription)")
        state = .disconnected
        cleanup(error)
        throw error
      }
    }
  }

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
      throw TransportError.operationFailed("SSE request did not return HTTP 2XX.")
    }
  }

  private func handleEndpointEvent(_ data: Data) throws {
    guard
      let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
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
  }

  private func resolvePostURL(timeout: TimeInterval = 5) async throws -> URL {
    if let existing = postURL { return existing }
    let (stream, continuation) = AsyncStream.makeStream(of: URL.self)
    postURLContinuations.append(continuation)
    return try await withThrowingTimeout(seconds: timeout) {
      for try await url in stream { return url }
      throw TransportError.invalidState("URL never resolved")
    }
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
