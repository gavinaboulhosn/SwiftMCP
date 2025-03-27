import Foundation

public struct ResourceListChangedNotification: MCPNotification {
  public static let method = "notifications/resources/list_changed"
  public var method: String { ResourceListChangedNotification.method }

  public struct Params: Codable, Sendable {
    public let _meta: [String: AnyCodable]?
  }

  public var params: Params

  public init(_meta: [String: AnyCodable]? = nil) {
    params = Params(_meta: _meta)
  }
}

public struct ResourceUpdatedNotification: MCPNotification {
  public static let method = "notifications/resources/updated"
  public var method: String { ResourceUpdatedNotification.method }

  public struct Params: Codable, Sendable {
    public let uri: String
  }

  public var params: Params

  public init(uri: String) {
    params = Params(uri: uri)
  }
}
