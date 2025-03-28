import Foundation

/// Sent from the client to request a list of tools the server has.
///
/// Defined in MCP spec under the "ListToolsRequest" definition:
/// ```json
/// {
///   "description": "Sent from the client to request a list of tools the server has.",
///   "properties": {
///     "method": {
///       "const": "tools/list",
///       "type": "string"
///     },
///     "params": {
///       "properties": {
///         "cursor": {
///           "description": "An opaque token representing the current pagination position.",
///           "type": "string"
///         }
///       },
///       "type": "object"
///     }
///   }
/// }
/// ```
public struct ListToolsRequest: MCPRequest {
  public static let method = "tools/list"
  public typealias Response = ListToolsResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let cursor: String?
  }

  public var params: Params

  public init(cursor: String? = nil) {
    params = Params(cursor: cursor)
  }
}
