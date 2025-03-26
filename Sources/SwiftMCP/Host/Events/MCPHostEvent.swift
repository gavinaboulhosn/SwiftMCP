import Foundation

/// Events emitted by an `MCPHost`:
/// - connectionAdded: A new connection was added
/// - connectionRemoved: A connection was removed
/// - connectionStatusChanged: The status of a connection changed
public enum MCPHostEvent {
  case connectionAdded(ConnectionState)
  case connectionRemoved(String)
  case connectionStatusChanged(ConnectionState)
}
