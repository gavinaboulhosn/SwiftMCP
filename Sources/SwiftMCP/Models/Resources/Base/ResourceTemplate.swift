import Foundation

public struct ResourceTemplate: Codable, Sendable, Identifiable, Hashable {
  public let name: String
  public let uriTemplate: String
  public let description: String?
  public let mimeType: String?
  public let annotations: Annotations?

  public var id: String {
    name + uriTemplate
  }
}
