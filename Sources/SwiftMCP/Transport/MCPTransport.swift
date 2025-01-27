import Foundation

/// A protocol describing the core transport interface for MCP.
/// It is an `Actor` so that transport operations are serialized.
public protocol MCPTransport: Actor {
  /// The current state of the transport
  var state: TransportState { get }
  /// Transport-level configuration
  var configuration: TransportConfiguration { get }

  /// Provides a stream of raw `Data` messages.
  /// This is used by `MCPClient` to receive inbound messages.
  func messages() -> AsyncThrowingStream<Data, Error>

  /// Start the transport, transitioning it from `.disconnected` to `.connecting` and eventually `.connected`.
  func start() async throws

  /// Stop the transport, closing any connections and cleaning up resources.
  func stop()

  /// Send data across the transport, optionally with a custom timeout.
  func send(_ data: Data, timeout: TimeInterval?) async throws
}

/// Default `send(_ data:timeout:)` with an optional parameter.
extension MCPTransport {
  public func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
    if data.count > configuration.maxMessageSize {
      throw TransportError.messageTooLarge(data.count)
    }
    let finalTimeout = timeout ?? configuration.sendTimeout
    try await with(timeout: .microseconds(Int64(finalTimeout * 1_000_000))) { [weak self] in
      guard let self else { return }
      try await self.send(data, timeout: nil)
    }
  }
}

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

  public var errorDescription: String? {
    switch self {
    case .timeout(let op):
      return "Timeout waiting for operation: \(op)"
    case .invalidMessage(let msg):
      return "Invalid message format: \(msg)"
    case .connectionFailed(let detail):
      return "Connection failed: \(detail)"
    case .operationFailed(let msg):
      return "Operation failed: \(msg)"
    case .invalidState(let reason):
      return "Invalid state: \(reason)"
    case .messageTooLarge(let size):
      return "Message exceeds size limit: \(size)"
    case .notSupported(let detail):
      return "Transport type not supported: \(detail)"
    }
  }
}
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

/// Conformance for printing or debugging `TransportState`.
extension TransportState: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    switch self {
    case .disconnected: return "disconnected"
    case .connecting: return "connecting"
    case .connected: return "connected"
    case .failed(let error): return "failed: \(error)"
    }
  }
  public var debugDescription: String { description }
}

extension TransportState: Equatable {
  public static func == (lhs: TransportState, rhs: TransportState) -> Bool {
    switch (lhs, rhs) {
    case (.disconnected, .disconnected),
      (.connecting, .connecting),
      (.connected, .connected),
      (.failed, .failed):
      return true
    default:
      return false
    }
  }
}

/// A protocol for transports to optionally provide a `withRetry` API.
public protocol RetryableTransport: MCPTransport {
  func withRetry<T>(
    operation: String,
    block: @escaping () async throws -> T
  ) async throws -> T
}

/// Default implementation of `withRetry`.
extension RetryableTransport {
  public func withRetry<T>(
    operation: String,
    block: @escaping () async throws -> T
  ) async throws -> T {
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
