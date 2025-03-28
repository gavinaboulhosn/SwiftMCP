import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "WebSocketClientTransport")

// MARK: - WebSocketClientTransport

extension WebSocketTransportConfiguration {
  public static let dummyData: WebSocketTransportConfiguration =
    try! WebSocketTransportConfiguration(
      endpointURL: URL(string: "ws://localhost:3000")!,
      baseConfiguration: .dummyData)
}

/// Configuration for a Websocket client transport
public struct WebSocketTransportConfiguration: Codable {

  // MARK: Lifecycle

  public init(
    endpointURL: URL,
    protocols: [String] = ["mcp"],
    baseConfiguration: TransportConfiguration = .default
  )
    throws
  {
    guard
      let scheme = endpointURL.scheme?.lowercased(),
      scheme == "ws" || scheme == "wss"
    else {
      throw TransportError.invalidURLScheme(endpointURL.scheme ?? "none")
    }

    self.endpointURL = endpointURL
    self.protocols = protocols
    self.baseConfiguration = baseConfiguration
  }

  // MARK: Public

  public var endpointURL: URL
  public var protocols: [String]
  // TODO: does cookie / auth storage need to be on here too?
  public var baseConfiguration: TransportConfiguration

}

public actor WebSocketClientTransport: MCPTransport, RetryableTransport {

  // MARK: Lifecycle

  // MARK: - Initialization

  public init(configuration: WebSocketTransportConfiguration) {
    _configuration = configuration

    delegate = WebSocketDelegate()
    session = URLSession(
      configuration: .ephemeral,
      delegate: delegate,
      // TODO: probably need queue to keep events synchronous
      delegateQueue: nil)
    // TODO: revisit auth settings
    session.configuration.httpShouldSetCookies = true
    session.configuration.httpCookieAcceptPolicy = .always
    session.configuration.timeoutIntervalForRequest = configuration.baseConfiguration.requestTimeout
    session.configuration.timeoutIntervalForResource =
      configuration.baseConfiguration.responseTimeout
    session.configuration.waitsForConnectivity = configuration.baseConfiguration.connectTimeout > 0

    // Create a weak reference to self to avoid retain cycles

    delegate.onOpen = { [weak self] in
      Task {
        await self?.handleOpen()
      }
    }

    delegate.onClose = { [weak self] reason in
      Task {
        await self?.onClose(reason)
      }
    }

    delegate.onError = { [weak self] error in
      Task {
        await self?.handleError(error)
      }
    }
  }

  deinit {
    // For Swift 6 compatibility, we cancel tasks directly without capturing self
    messageReceiverTask?.cancel()
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
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

  public var configuration: TransportConfiguration { _configuration.baseConfiguration }

  public var messages: AsyncThrowingStream<JSONRPCMessage, Error> {
    get throws {
      let (stream, continuation) = AsyncThrowingStream.makeStream(of: JSONRPCMessage.self)
      messageContinuation = continuation
      return stream
    }
  }

  public var stateMessages: AsyncStream<TransportState> {
    get throws {
      let (stream, continuation) = AsyncStream.makeStream(of: TransportState.self)
      transportStateContinuation = continuation
      return stream
    }
  }

  // MARK: - Public Interface

  public func start() async throws {
    guard state != .connected else {
      throw TransportError.invalidState("already connected, no need to start")
    }

    state = .connecting
    webSocketTask = session.webSocketTask(with: url, protocols: _configuration.protocols)
    webSocketTask?.resume()
  }

  public func stop() {
    state = .disconnected
    cleanup(nil)
  }

  public func send(_ message: JSONRPCMessage, timeout _: TimeInterval? = nil) async throws {
    guard state == .connected else {
      throw TransportError.invalidState("Not connected")
    }
    let data = try validate(message)
    try await withRetry(operation: "WS SendMessage") {
      try await self.webSocketTask?.send(.data(data))
    }
  }

  // MARK: Internal

  private(set) var url: URL {
    get { _configuration.endpointURL }
    set { _configuration.endpointURL = newValue }
  }

  // MARK: Private

  private var _configuration: WebSocketTransportConfiguration

  private var webSocketTask: URLSessionWebSocketTask?
  private let session: URLSession
  private let delegate: WebSocketDelegate

  private var messageReceiverTask: Task<Void, Error>?
  private var messageContinuation: AsyncThrowingStream<JSONRPCMessage, Error>.Continuation?
  private var transportStateContinuation: AsyncStream<TransportState>.Continuation?

  // TODO: expand cancellation reason support
  private func cleanup(_ error: Error?) {
    messageReceiverTask?.cancel()
    messageReceiverTask = nil
    messageContinuation?.finish(throwing: error)
    messageContinuation = nil
    transportStateContinuation?.finish()
    transportStateContinuation = nil
    // TODO : revisit these exit codes
    if error != nil {
      webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
    } else {
      webSocketTask?.cancel(with: .normalClosure, reason: nil)
    }
    webSocketTask = nil
  }

  private func onClose(_ reason: String) {
    logger.info("WebSocket closed with reason: \(reason). Transitioning to disconnected.")
    let err = TransportError.connectionFailed(reason)
    state = .disconnected
    cleanup(err)
  }

  // MARK: - Private Handlers

  private func handleOpen() {
    state = .connected
    startMessageReceiver()
  }

  /// Cleanups subscriptions and bubbles up error to all subscribers
  private func handleError(_ error: Error) {
    logger.error(
      "WebSocket encountered error: \(error.localizedDescription). Transitioning to disconnected.")
    state = .disconnected
    cleanup(error)
  }

  private func startMessageReceiver() {
    // Prevent multiple receiver tasks from being created.
    if messageReceiverTask != nil {
      logger.warning("Message receiver task already running. Ignoring duplicate start.")
      return
    }

    messageReceiverTask = Task {
      // Extract the URL string for logging.
      let endpointURL = url.absoluteString
      do {
        while true {
          try Task.checkCancellation()
          guard let wsTask = webSocketTask else {
            throw TransportError.invalidState("No WebSocket Task available")
          }
          // Continuously receive messages.
          let message = try await wsTask.receive()
          try await handleMessage(message)
        }
      } catch is CancellationError {
        logger.debug("WebSocket message receiver cancelled for URL: \(endpointURL)")
      } catch {
        logger.error(
          "Fatal error in WebSocket read loop for URL \(endpointURL): \(error.localizedDescription)"
        )
        state = .disconnected
        cleanup(error)
      }
    }
  }

  private func handleMessage(_ message: URLSessionWebSocketTask.Message) async throws {
    switch message {
    case .data(let data):
      messageContinuation?.yield(try parse(data))

    case .string(let text):
      if let data = text.data(using: .utf8) {
        messageContinuation?.yield(try parse(data))
      }

    @unknown default:
      logger.warning("Received unknown WebSocket message type")
    }
  }
}

// MARK: - WebSocketDelegate

private class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
  var onOpen: (() -> Void)?
  var onClose: ((String) -> Void)?
  var onError: ((Error) -> Void)?

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didOpenWithProtocol _: String?
  ) {
    onOpen?()
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith _: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    let message = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    onClose?(message)
  }

  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error = error {
      onError?(error)
    }
  }
}
