import Foundation

/// The server's response to a tools/list request from the client.
///
/// Defined in MCP spec under the "ListToolsResult" definition:
/// ```json
/// {
///   "description": "The server's response to a tools/list request from the client.",
///   "properties": {
///     "_meta": {
///       "additionalProperties": {},
///       "type": "object"
///     },
///     "nextCursor": {
///       "description": "An opaque token representing the pagination position after the last returned result.",
///       "type": "string"
///     },
///     "tools": {
///       "items": {
///         "$ref": "#/definitions/Tool"
///       },
///       "type": "array"
///     }
///   },
///   "required": ["tools"]
/// }
/// ```
public struct ListToolsResult: MCPResponse {
    public typealias Request = ListToolsRequest

    /// Additional metadata about the response.
    public var _meta: [String: AnyCodable]?

    /// The list of tools available on the server.
    public let tools: [MCPTool]

    /// An opaque token representing the pagination position after the last returned result.
    /// If present, there may be more results available.
    public let nextCursor: String?
}
