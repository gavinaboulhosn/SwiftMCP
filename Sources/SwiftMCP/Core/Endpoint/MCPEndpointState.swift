import Foundation

/// Common state representation for MCP endpoints
public enum MCPEndpointState<State: Equatable>: Equatable {
  /// Endpoint is disconnected
  case disconnected

  /// Endpoint is connecting
  case connecting

  /// Endpoint is performing initialization
  case initializing

  /// Endpoint is running with negotiated capabilities
  case running(State)

  /// Endpoint has failed
  case failed(Error)

  // MARK: Public

  public static func ==(lhs: MCPEndpointState, rhs: MCPEndpointState) -> Bool {
    switch (lhs, rhs) {
    case (.disconnected, .disconnected),
         (.connecting, .connecting),
         (.initializing, .initializing):
      true
    case (.running(let lCap), .running(let rCap)):
      lCap == rCap
    case (.failed, .failed):
      // Don't compare errors, just that both are failed
      true
    default:
      false
    }
  }
}
