import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "WebSocketClientTransport")

// MARK: - WebSocketClientTransport

public actor WebSocketClientTransport: MCPTransport {

  // MARK: Lifecycle

  // MARK: - Initialization

  public init(url: URL, configuration: TransportConfiguration = .default) {
    self.url = url
    self.configuration = configuration

    delegate = WebSocketDelegate()
    session = URLSession(
      configuration: .ephemeral,
      delegate: delegate,
      delegateQueue: nil
    )

    delegate.onOpen = { [weak self] in
      Task { await self?.handleOpen() }
    }

    delegate.onClose = { [weak self] reason in
      Task { await self?.handleError(TransportError.connectionFailed(reason)) }
    }

    delegate.onError = { [weak self] error in
      Task { await self?.handleError(error) }
    }
  }

  deinit {
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    connectContinuation?.resume(throwing: CancellationError())
    messageContinuation?.finish()
  }

  // MARK: Public

  public var configuration: TransportConfiguration
  public private(set) var state = TransportState.disconnected

  // MARK: - Public Interface

  public func start() async throws {
    guard state != .connected else { return }

    state = .connecting
    webSocketTask?.cancel()
    webSocketTask = session.webSocketTask(with: url, protocols: ["mcp"])
    webSocketTask?.resume()

    try await withCheckedThrowingContinuation { continuation in
      connectContinuation = continuation
    }
  }

  public func stop() {
    state = .disconnected
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    connectContinuation?.resume(throwing: CancellationError())
    messageContinuation?.finish()
  }

  public func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
    guard state == .connected else {
      throw TransportError.invalidState("Not connected")
    }

    try await webSocketTask?.send(.data(data))
  }

  public func messages() -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      messageContinuation = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.stop() }
      }
    }
  }

  // MARK: Private

  private let url: URL
  private var webSocketTask: URLSessionWebSocketTask?
  private let session: URLSession
  private let delegate: WebSocketDelegate

  private var connectContinuation: CheckedContinuation<Void, Error>?
  private var messageContinuation: AsyncThrowingStream<Data, Error>.Continuation?

  // MARK: - Private Handlers

  private func handleOpen() {
    state = .connected
    connectContinuation?.resume()
    connectContinuation = nil
    startMessageReceiver()
  }

  private func handleError(_ error: Error) {
    state = .failed(error)
    connectContinuation?.resume(throwing: error)
    connectContinuation = nil
    messageContinuation?.finish(throwing: error)
  }

  private func startMessageReceiver() {
    Task {
      guard let webSocketTask = webSocketTask else { return }

      do {
        // not sure if this is really accurate, might want to use webSocketTask?.state
        // most implementations just recursively call receive() in a defer
        // defer { receive() }
        while state == .connected {
          let message = try await webSocketTask.receive()
          try await handleMessage(message)
        }

        logger.error("No longer handling messages")
      } catch {
        handleError(error)
      }
    }
  }

  private func handleMessage(_ message: URLSessionWebSocketTask.Message) async throws {
    switch message {
    case .data(let data):
      messageContinuation?.yield(data)

    case .string(let text):
      if let data = text.data(using: .utf8) {
        messageContinuation?.yield(data)
      }

    @unknown default:
      logger.warning("Received unknown message type")
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
    didOpenWithProtocol _: String?)
  {
    onOpen?()
  }

  func urlSession(
    _: URLSession,
    webSocketTask _: URLSessionWebSocketTask,
    didCloseWith _: URLSessionWebSocketTask.CloseCode,
    reason: Data?)
  {
    let message = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    onClose?(message)
  }

  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didCompleteWithError error: Error?)
  {
    if let error = error {
      onError?(error)
    }
  }
}
