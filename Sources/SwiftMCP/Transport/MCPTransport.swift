import Foundation

// MARK: - MCPTransport

/// A protocol describing the core transport interface for MCP.
/// It is an `Actor` so that transport operations are serialized.
public protocol MCPTransport: Actor {
  /// The current state of the transport
  var state: TransportState { get }

  /// Current transport-level configuration
  var configuration: TransportConfiguration { get }

  /// A live stream of the current transport state
  var stateMessages: AsyncStream<TransportState> { get throws }

  /// Provides a stream of raw `JSONRPCMessage` messages.
  /// This is used by `MCPClient` to receive inbound messages.
  var messages: AsyncThrowingStream<JSONRPCMessage, Error> { get throws }

  /// Start the transport, transitioning it from `.disconnected` to `.connecting` and eventually `.connected`.
  func start() async throws

  /// Stop the transport, closing any connections and cleaning up resources.
  func stop()

  /// Send data across the transport, optionally with a custom timeout.
  func send(_ data: JSONRPCMessage, timeout: TimeInterval?) async throws

}

// MARK: - TransportError

/// Common errors at the transport layer (outside the scope of `MCPError`).
public enum TransportError: Error, LocalizedError {
  /// Timed out waiting for an operation
  case timeout(operation: String)
  /// Invalid message format
  case invalidMessage(String)
  /// Unable to connect or connection lost
  case connectionFailed(String)
  /// A general operation failure
  case operationFailed(String)
  /// Transport not in a valid state
  case invalidState(String)
  /// Message size exceeded
  case messageTooLarge(Int)
  /// Transport type not supported on this platform
  case notSupported(String)
  /// Invalid URL scheme for transport
  case invalidURLScheme(String)

  // MARK: Public

  public var errorDescription: String? {
    switch self {
    case .timeout(let op):
      "Timeout waiting for operation: \(op)"
    case .invalidMessage(let msg):
      "Invalid message format: \(msg)"
    case .connectionFailed(let detail):
      "Connection failed: \(detail)"
    case .operationFailed(let msg):
      "Operation failed: \(msg)"
    case .invalidState(let reason):
      "Invalid state: \(reason)"
    case .messageTooLarge(let size):
      "Message exceeds size limit: \(size)"
    case .notSupported(let detail):
      "Transport type not supported: \(detail)"
    case .invalidURLScheme(let scheme):
      "Invalid URL scheme for WebSocket transport: \(scheme). Must be 'ws' or 'wss'"
    }
  }
}

// MARK: - TransportState

/// Represents the high-level connection state of a transport.
public enum TransportState {
  /// Transport is not connected
  case disconnected
  /// Transport is in the process of connecting
  case connecting
  /// Transport is connected
  case connected
  /// Transport has failed
  case failed(Error)
}

// MARK: CustomStringConvertible, CustomDebugStringConvertible

/// Conformance for printing or debugging `TransportState`.
extension TransportState: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    switch self {
    case .disconnected: "disconnected"
    case .connecting: "connecting"
    case .connected: "connected"
    case .failed(let error): "failed: \(error)"
    }
  }

  public var debugDescription: String { description }
}

// MARK: Equatable

extension TransportState: Equatable {
  public static func ==(lhs: TransportState, rhs: TransportState) -> Bool {
    switch (lhs, rhs) {
    case (.disconnected, .disconnected),
         (.connecting, .connecting),
         (.connected, .connected),
         (.failed, .failed):
      true
    default:
      false
    }
  }
}

// MARK: - RetryableTransport

/// A protocol for transports to optionally provide a `withRetry` API.
public protocol RetryableTransport: MCPTransport {
  func withRetry<T>(
    operation: String,
    block: @escaping () async throws -> T) async throws -> T
}

/// Default implementation of `withRetry`.
extension RetryableTransport {
  public func withRetry<T>(
    operation _: String,
    block: @escaping () async throws -> T)
    async throws -> T
  {
    var attempt = 1
    var lastError: Error?

    while attempt <= configuration.retryPolicy.maxAttempts {
      do {
        return try await block()
      } catch {
        lastError = error
        // If we've used all attempts, stop
        guard attempt < configuration.retryPolicy.maxAttempts else { break }

        let delay = configuration.retryPolicy.delay(forAttempt: attempt)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        attempt += 1
      }
    }
    throw TransportError.operationFailed("\(String(describing: lastError))")
  }
}

extension MCPTransport {
  /// Default `send(_ message:timeout:)` with an optional parameter.
  public func send(_ message: JSONRPCMessage, timeout: TimeInterval? = nil) async throws {
    try await send(message, timeout: timeout)
  }

  /// Validates messages before sending
  public func validate(_ message: JSONRPCMessage) throws -> Data {
    let bytes: Data
    do {
      bytes = try JSONEncoder().encode(message)
    } catch {
      throw TransportError.operationFailed("Failed to serialize message: \(error.localizedDescription)")
    }
    let messageSize = bytes.count
    let maxMessageSize = configuration.maxMessageSize
    if messageSize > maxMessageSize {
      throw TransportError.messageTooLarge(messageSize)
    }
    return bytes
  }

  /// Parses message from data
  public func parse(_ data: Data) throws -> JSONRPCMessage {
    guard let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) else {
      throw TransportError.invalidMessage("Unable to parse JSONRPCMessage from data: \(data)")
    }
    return message
  }

}

extension MCPTransport {
  func startHealthCheckTask() async throws {
    guard state == .connected else {
      // not connected, why are we pinging?!?!??!
      return
    }
    try await ping()
    try await Task.sleep(for: .seconds(configuration.healthCheckInterval))
  }

  /// Sends a ping to the server
  func ping() async throws {
   let requestId = UUID().uuidString
   let message = JSONRPCMessage.request(id: .string(requestId), request: PingRequest())
   let result = try await send(message)
  }
}
