import Foundation

public struct Implementation: Codable, Sendable, Equatable {
  public let name: String
  public let version: String

  public init(name: String, version: String) {
    self.name = name
    self.version = version
  }

  public static let defaultClient = Implementation(
    name: Bundle.main.bundleIdentifier ?? "SwiftMCP",
    version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
}
