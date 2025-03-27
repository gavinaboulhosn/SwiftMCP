import Foundation

public struct MCPResource: Codable, Sendable, Identifiable, Hashable {
  public let uri: String
  public let name: String
  public let description: String?
  public let mimeType: String?

  public var id: String { uri }
}
