import Foundation

public enum ResourceContentsVariant: Codable, Sendable {
  case text(TextResourceContents)
  case blob(BlobResourceContents)

  // MARK: Lifecycle

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let textResource = try? container.decode(TextResourceContents.self) {
      self = .text(textResource)
      return
    }
    if let blobResource = try? container.decode(BlobResourceContents.self) {
      self = .blob(blobResource)
      return
    }
    throw DecodingError.dataCorruptedError(
      in: container, debugDescription: "Invalid resource contents")
  }

  // MARK: Public

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .text(let textResource):
      try textResource.encode(to: encoder)
    case .blob(let blobResource):
      try blobResource.encode(to: encoder)
    }
  }
}
