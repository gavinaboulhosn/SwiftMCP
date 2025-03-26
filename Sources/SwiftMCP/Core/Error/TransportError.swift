import Foundation

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
