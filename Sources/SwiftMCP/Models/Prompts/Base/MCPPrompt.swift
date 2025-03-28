import Foundation

/// A prompt or prompt template that the server offers.
///
/// MCP Schema:
/// ```json
/// {
///   "description": "A prompt or prompt template that the server offers.",
///   "properties": {
///     "name": {
///       "description": "The name of the prompt or prompt template.",
///       "type": "string"
///     },
///     "description": {
///       "description": "An optional description of what this prompt provides",
///       "type": "string"
///     },
///     "arguments": {
///       "description": "A list of arguments to use for templating the prompt.",
///       "items": { "$ref": "#/definitions/PromptArgument" },
///       "type": "array"
///     }
///   },
///   "required": ["name"],
///   "type": "object"
/// }
/// ```
public struct MCPPrompt: Codable, Sendable, Hashable, Identifiable {

  // MARK: Lifecycle

  public init(
    name: String,
    description: String? = nil,
    arguments: [PromptArgument]? = nil)
  {
    self.name = name
    self.description = description
    self.arguments = arguments
  }

  // MARK: Public

  /// The name of the prompt or prompt template.
  public let name: String

  /// An optional description of what this prompt provides.
  public let description: String?

  /// A list of arguments to use for templating the prompt.
  public let arguments: [PromptArgument]?

  public var id: String { name }

}
