import Foundation

/// The server's response to a prompts/list request from the client.
///
/// MCP Schema:
/// ```json
/// {
///   "description": "The server's response to a prompts/list request from the client.",
///   "properties": {
///     "_meta": {
///       "additionalProperties": {},
///       "description": "This result property is reserved by the protocol to allow clients and servers to attach additional metadata to their responses.",
///       "type": "object"
///     },
///     "nextCursor": {
///       "description": "An opaque token representing the pagination position after the last returned result. If present, there may be more results available.",
///       "type": "string"
///     },
///     "prompts": {
///       "items": {
///         "$ref": "#/definitions/Prompt"
///       },
///       "type": "array"
///     }
///   },
///   "required": ["prompts"],
///   "type": "object"
/// }
/// ```
public struct ListPromptsResult: MCPResponse {
  public typealias Request = ListPromptsRequest

  public var _meta: [String: AnyCodable]?

  /// The list of available prompts.
  public let prompts: [MCPPrompt]

  /// An opaque token representing the pagination position after the last returned result.
  /// If present, there may be more results available.
  public let nextCursor: String?

  public init(
    prompts: [MCPPrompt],
    nextCursor: String? = nil,
    metadata: [String: AnyCodable]? = nil
  ) {
    self.prompts = prompts
    self.nextCursor = nextCursor
    _meta = metadata
  }
}
