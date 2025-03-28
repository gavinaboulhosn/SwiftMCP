import Foundation

/// The server's response to a tool call.
///
/// Defined in MCP spec under the "CallToolResult" definition:
/// ```json
/// {
///   "description": "The server's response to a tool call.",
///   "properties": {
///     "_meta": {
///       "additionalProperties": {},
///       "type": "object"
///     },
///     "content": {
///       "items": {
///         "anyOf": [
///           { "$ref": "#/definitions/TextContent" },
///           { "$ref": "#/definitions/ImageContent" },
///           { "$ref": "#/definitions/EmbeddedResource" }
///         ]
///       },
///       "type": "array"
///     },
///     "isError": {
///       "description": "Whether the tool call ended in an error.",
///       "type": "boolean"
///     }
///   },
///   "required": ["content"]
/// }
/// ```
public struct CallToolResult: MCPResponse {
  public typealias Request = CallToolRequest

  /// The content returned by the tool.
  public let content: [ToolContent]

  /// Whether the tool call ended in an error.
  /// If not set, this is assumed to be false (the call was successful).
  public let isError: Bool?

  /// Additional metadata about the response.
  public var _meta: [String: AnyCodable]?
}
