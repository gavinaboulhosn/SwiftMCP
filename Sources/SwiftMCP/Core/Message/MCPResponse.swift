import Foundation

/// Protocol for response messages
public protocol MCPResponse: MCPMessage {
  /// The request type this response corresponds to
  associatedtype Request: MCPRequest where Request.Response == Self

  var _meta: [String: AnyCodable]? { get set }
}
