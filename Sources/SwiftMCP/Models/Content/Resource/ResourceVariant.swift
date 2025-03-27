import Foundation

/// Resource content can be either text or blob
public enum ResourceContentVariant: Codable, Sendable, Hashable {
    case text(TextResourceContents)
    case blob(BlobResourceContents)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try text first
        if let textResource = try? container.decode(TextResourceContents.self) {
            // must have text present
            if textResource.text.isEmpty {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "TextResourceContents must have text")
            }
            self = .text(textResource)
            return
        }

        // Try blob
        if let blobResource = try? container.decode(BlobResourceContents.self) {
            self = .blob(blobResource)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Resource must be either TextResourceContents or BlobResourceContents")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let textResource):
            try container.encode(textResource)
        case .blob(let blobResource):
            try container.encode(blobResource)
        }
    }
}
