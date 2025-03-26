import Foundation

/// Events that a `ConnectionState` can emit, e.g., status changes.
public enum ConnectionStateEvent {
  /// The connection's status changed
  case statusChanged(ConnectionStatus)
  case clientError(Error)
}
