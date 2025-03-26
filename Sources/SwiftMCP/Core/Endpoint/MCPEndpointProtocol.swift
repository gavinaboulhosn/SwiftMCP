import Foundation
import OSLog

/// Protocol defining common behavior for MCP endpoints
public protocol MCPEndpointProtocol: Actor {
  associatedtype SessionInfo: Equatable

  /// Current endpoint state
  var state: MCPEndpointState<SessionInfo> { get }

  /// Stream of notifications from this endpoint
  var notifications: AsyncStream<any MCPNotification> { get }

  /// Start the endpoint with the given transport
  func start(_ transport: MCPTransport) async throws

  /// Stop the endpoint
  func stop(cancelPending: Bool) async

  /// Send a request and await response
  func send<R: MCPRequest>(_ request: R) async throws -> R.Response
}
