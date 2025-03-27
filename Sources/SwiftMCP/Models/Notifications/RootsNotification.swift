import Foundation

public struct RootsListChangedNotification: MCPNotification {
  public static let method = "notifications/roots/list_changed"
  public var method: String { RootsListChangedNotification.method }

  public struct Params: Codable, Sendable {
    public let _meta: [String: AnyCodable]?
  }

  public var params: Params

  public init(_meta: [String: AnyCodable]? = nil) {
    params = Params(_meta: _meta)
  }
}
