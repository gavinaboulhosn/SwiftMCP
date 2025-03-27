import Foundation

/// Describes a message returned as part of a prompt.
///
/// This is similar to `SamplingMessage`, but also supports the embedding of
/// resources from the MCP server.
///
/// MCP Schema:
/// ```json
/// {
///   "description": "Describes a message returned as part of a prompt.",
///   "properties": {
///     "role": {
///       "$ref": "#/definitions/Role"
///     },
///     "content": {
///       "anyOf": [
///         { "$ref": "#/definitions/TextContent" },
///         { "$ref": "#/definitions/ImageContent" },
///         { "$ref": "#/definitions/AudioContent" },
///         { "$ref": "#/definitions/EmbeddedResource" }
///       ]
///     }
///   },
///   "required": ["content", "role"],
///   "type": "object"
/// }
/// ```
public struct PromptMessage: Codable, Sendable, Hashable {
  /// The role of the message sender (user or assistant).
  public let role: Role

  /// The content of the message.
  public let content: PromptContent

  public init(
    role: Role,
    content: PromptContent
  ) {
    self.role = role
    self.content = content
  }
}

/// The content of a prompt message.
public enum PromptContent: Codable, Sendable, Hashable {
  case text(TextContent)
  case image(ImageContent)
  case resource(EmbeddedResourceContent)

  // MARK: - Codable

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let textContent = try? container.decode(TextContent.self),
      textContent.type == .text
    {
      self = .text(textContent)
      return
    }
    if let imageContent = try? container.decode(ImageContent.self),
      imageContent.type == .image
    {
      self = .image(imageContent)
      return
    }
    if let resourceContent = try? container.decode(EmbeddedResourceContent.self),
      resourceContent.type == .resource
    {
      self = .resource(resourceContent)
      return
    }
    throw DecodingError.dataCorruptedError(
      in: container, debugDescription: "Invalid PromptContent")
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .text(let textContent): try container.encode(textContent)
    case .image(let imageContent): try container.encode(imageContent)
    case .resource(let resourceContent): try container.encode(resourceContent)
    }
  }
}
