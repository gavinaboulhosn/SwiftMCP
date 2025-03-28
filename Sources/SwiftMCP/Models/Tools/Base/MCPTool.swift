import Foundation
@preconcurrency import JSONSchema

/// A tool that can be called by the client.
///
/// Defined in MCP spec under the "Tool" definition:
/// ```json
/// {
///   "description": "Definition for a tool the client can call.",
///   "properties": {
///     "name": {
///       "description": "The name of the tool.",
///       "type": "string"
///     },
///     "description": {
///       "description": "A human-readable description of the tool.",
///       "type": "string"
///     },
///     "inputSchema": {
///       "description": "A JSON Schema object defining the expected parameters for the tool.",
///       "properties": {
///         "type": { "const": "object" }
///       }
///     },
///     "annotations": {
///       "$ref": "#/definitions/ToolAnnotations",
///       "description": "Optional additional tool information."
///     }
///   },
///   "required": ["inputSchema", "name"]
/// }
/// ```
public struct MCPTool: Codable, Sendable, Identifiable, Hashable {

  // MARK: Lifecycle

  public init(
    name: String,
    description: String? = nil,
    inputSchema: Schema,
    annotations: ToolAnnotations? = nil)
  {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
    self.annotations = annotations
  }

  // MARK: Public

  public typealias ToolInputSchema = Schema

  /// The name of the tool.
  public let name: String

  /// A human-readable description of what this tool does.
  /// This can be used by clients to improve the LLM's understanding of available tools.
  public let description: String?

  /// The input schema for the tool, defining expected parameters.
  public let inputSchema: ToolInputSchema

  /// Optional additional tool information.
  public let annotations: ToolAnnotations?

  public var id: String { name }

  // MARK: - Equatable

  public static func ==(lhs: MCPTool, rhs: MCPTool) -> Bool {
    lhs.name == rhs.name &&
      lhs.description == rhs.description &&
      lhs.annotations == rhs.annotations
  }

  // MARK: - Hashable

  public func hash(into hasher: inout Hasher) {
    hasher.combine(name)
    hasher.combine(description)
    hasher.combine(annotations)
  }
}
