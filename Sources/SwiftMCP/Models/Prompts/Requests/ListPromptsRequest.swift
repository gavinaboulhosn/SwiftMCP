import Foundation

/// Sent from the client to request a list of prompts and prompt templates the server has.
///
/// MCP Schema:
/// ```json
/// {
///   "description": "Sent from the client to request a list of prompts and prompt templates the server has.",
///   "properties": {
///     "method": {
///       "const": "prompts/list",
///       "type": "string"
///     },
///     "params": {
///       "properties": {
///         "cursor": {
///           "description": "An opaque token representing the current pagination position. If provided, the server should return results starting after this cursor.",
///           "type": "string"
///         }
///       },
///       "type": "object"
///     }
///   },
///   "required": ["method"],
///   "type": "object"
/// }
/// ```
public struct ListPromptsRequest: MCPRequest, Sendable {
  public static let method = "prompts/list"
  public typealias Response = ListPromptsResult

  public struct Params: MCPRequestParams, Sendable {
    public var _meta: RequestMeta?

    /// An opaque token representing the current pagination position.
    /// If provided, the server should return results starting after this cursor.
    public let cursor: String?
  }

  public var params: Params

  public init(cursor: String? = nil) {
    params = Params(cursor: cursor)
  }
}
