import Foundation

/// Content returned from a tool call.
///
/// Defined in MCP spec under the "CallToolResult" definition:
/// ```json
/// {
///   "content": {
///     "items": {
///       "anyOf": [
///         { "$ref": "#/definitions/TextContent" },
///         { "$ref": "#/definitions/ImageContent" },
///         { "$ref": "#/definitions/EmbeddedResource" }
///       ]
///     },
///     "type": "array"
///   }
/// }
/// ```
public enum ToolContent: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case resource(EmbeddedResourceContent)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(TextContent.self), text.type == .text {
            self = .text(text)
        } else if let image = try? container.decode(ImageContent.self), image.type == .image {
            self = .image(image)
        } else if let resource = try? container.decode(EmbeddedResourceContent.self), resource.type == .resource {
            self = .resource(resource)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Content must be TextContent, ImageContent, or EmbeddedResource"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text): try text.encode(to: encoder)
        case .image(let image): try image.encode(to: encoder)
        case .resource(let resource): try resource.encode(to: encoder)
        }
    }
}
