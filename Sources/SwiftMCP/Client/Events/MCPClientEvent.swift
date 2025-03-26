import Foundation

/// Events emitted by `MCPClient`, bridging some internal states and messages.
public enum MCPClientEvent {
  /// Connection state changed (connecting, running, disconnected, etc.)
  case connectionChanged(MCPEndpointState<InitializeResult>)
  /// Incoming MCP message (JSON-RPC request/notification from server)
  case message(any MCPMessage)
  /// Indicates an error encountered in the MCP client
  case error(Error)
}
