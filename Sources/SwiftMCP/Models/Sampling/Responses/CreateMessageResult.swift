import Foundation

/// The client's response to a sampling/create_message request from the server.
/// The client should inform the user before returning the sampled message, to allow them
/// to inspect the response (human in the loop) and decide whether to allow the server to see it.
public struct CreateMessageResult: MCPResponse {
    public typealias Request = CreateMessageRequest

    public enum CreateMessageContentVariant: Codable, Sendable {
        case text(TextContent)
        case image(ImageContent)
        case audio(AudioContent)

        // MARK: Lifecycle

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let textContent = try? container.decode(TextContent.self), textContent.type == .text {
                self = .text(textContent)
                return
            }
            if let imageContent = try? container.decode(ImageContent.self), imageContent.type == .image {
                self = .image(imageContent)
                return
            }
            if let audioContent = try? container.decode(AudioContent.self), audioContent.type == .audio {
                self = .audio(audioContent)
                return
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid content for CreateMessageResult"
            )
        }

        // MARK: Public

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .text(let textContent): try textContent.encode(to: encoder)
            case .image(let imageContent): try imageContent.encode(to: encoder)
            case .audio(let audioContent): try audioContent.encode(to: encoder)
            }
        }
    }

    public var _meta: [String: AnyCodable]?
    /// The content of the generated message
    public let content: CreateMessageContentVariant
    /// The name of the model that generated the message
    public let model: String
    /// The role of the message sender
    public let role: Role
    /// The reason why sampling stopped, if known
    public let stopReason: String?

    public init(
        _meta: [String: AnyCodable]? = nil,
        content: CreateMessageContentVariant,
        model: String,
        role: Role,
        stopReason: String? = nil
    ) {
        self._meta = _meta
        self.content = content
        self.model = model
        self.role = role
        self.stopReason = stopReason
    }
}
