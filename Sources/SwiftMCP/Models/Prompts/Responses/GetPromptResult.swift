import Foundation

/// The server's response to a prompts/get request from the client.
///
/// MCP Schema:
/// ```json
/// {
///   "description": "The server's response to a prompts/get request from the client.",
///   "properties": {
///     "_meta": {
///       "additionalProperties": {},
///       "description": "This result property is reserved by the protocol to allow clients and servers to attach additional metadata to their responses.",
///       "type": "object"
///     },
///     "description": {
///       "description": "An optional description for the prompt.",
///       "type": "string"
///     },
///     "messages": {
///       "items": {
///         "$ref": "#/definitions/PromptMessage"
///       },
///       "type": "array"
///     }
///   },
///   "required": ["messages"],
///   "type": "object"
/// }
/// ```
public struct GetPromptResult: MCPResponse, Sendable {
  public typealias Request = GetPromptRequest

  public var _meta: [String: AnyCodable]?

  /// An optional description for the prompt.
  public let description: String?

  /// The messages that make up the prompt.
  public let messages: [PromptMessage]

  public init(
    description: String? = nil,
    messages: [PromptMessage],
    metadata: [String: AnyCodable]? = nil)
  {
    self.description = description
    self.messages = messages
    _meta = metadata
  }
}
