import Foundation

/// Root definition
public struct Root: Codable, Sendable, Equatable {
  public let uri: String
  public let name: String?

  public init(uri: String, name: String? = nil) {
    self.uri = uri
    self.name = name
  }
}
