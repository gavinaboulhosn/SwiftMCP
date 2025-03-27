import Foundation

public struct InitializedNotification: MCPNotification {
  public static let method = "notifications/initialized"
  public var method: String { InitializedNotification.method }

  public struct Params: Codable, Sendable {
    public let _meta: [String: AnyCodable]?
  }

  public var params: Params

  public init(_meta: [String: AnyCodable]? = nil) {
    params = Params(_meta: _meta)
  }
}
