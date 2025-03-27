import Foundation

/// Describes an argument that a prompt can accept.
///
/// MCP Schema:
/// ```json
/// {
///   "description": "Describes an argument that a prompt can accept.",
///   "properties": {
///     "name": {
///       "description": "The name of the argument.",
///       "type": "string"
///     },
///     "description": {
///       "description": "A human-readable description of the argument.",
///       "type": "string"
///     },
///     "required": {
///       "description": "Whether this argument must be provided.",
///       "type": "boolean"
///     }
///   },
///   "required": ["name"],
///   "type": "object"
/// }
/// ```
public struct PromptArgument: Codable, Sendable, Hashable {
  /// The name of the argument.
  public let name: String

  /// A human-readable description of the argument.
  public let description: String?

  /// Whether this argument must be provided.
  public let required: Bool?

  public init(
    name: String,
    description: String? = nil,
    required: Bool? = nil
  ) {
    self.name = name
    self.description = description
    self.required = required
  }
}
