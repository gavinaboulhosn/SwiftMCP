import Foundation

/// Describes a message issued to or received from an LLM API.
public struct SamplingMessage: Codable, Sendable {

  // MARK: Lifecycle

  public init(role: Role, content: SamplingContent) {
    self.role = role
    self.content = content
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    role = try container.decode(Role.self, forKey: .role)
    content = try container.decode(SamplingContent.self, forKey: .content)
  }

  // MARK: Public

  /// The content variants that can be included in a sampling message
  public enum SamplingContent: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case audio(AudioContent)

    // MARK: Lifecycle

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let type = try container.decode(ContentType.self, forKey: .type)

      switch type {
      case .text:
        let content = try TextContent(from: decoder)
        self = .text(content)

      case .image:
        let content = try ImageContent(from: decoder)
        self = .image(content)

      case .audio:
        let content = try AudioContent(from: decoder)
        self = .audio(content)

      case .resource:
        throw DecodingError.dataCorruptedError(
          forKey: .type,
          in: container,
          debugDescription: "Resource type not supported in SamplingContent")
      }
    }

    // MARK: Public

    public func encode(to encoder: Encoder) throws {
      switch self {
      case .text(let textContent): try textContent.encode(to: encoder)
      case .image(let imageContent): try imageContent.encode(to: encoder)
      case .audio(let audioContent): try audioContent.encode(to: encoder)
      }
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
      case type
    }
  }

  public let role: Role
  public let content: SamplingContent

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(role, forKey: .role)
    try container.encode(content, forKey: .content)
  }

  // MARK: Private

  // MARK: Codable

  private enum CodingKeys: String, CodingKey {
    case role
    case content
  }

}
