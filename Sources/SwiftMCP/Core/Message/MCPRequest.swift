import Foundation

// MARK: - MCPRequest

/// Protocol for request messages.
///
/// Conforming types specify a request method, associated response type, and parameters.
public protocol MCPRequest: MCPMessage {
  associatedtype Response: MCPResponse where Response.Request == Self
  associatedtype Params: MCPRequestParams = EmptyParams

  /// The JSON-RPC method name for this request.
  static var method: String { get }

  /// The request parameters, if any.
  var params: Params { get set }
}

extension MCPRequest {
  public var params: EmptyParams { EmptyParams() }
}
