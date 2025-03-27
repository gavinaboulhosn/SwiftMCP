import Foundation

public struct ToolListChangedNotification: MCPNotification {
  public static let method = "notifications/tools/list_changed"
  public var method: String { ToolListChangedNotification.method }

  public struct Params: Codable, Sendable {
    public let _meta: [String: AnyCodable]?
  }

  public var params: Params

  public init(_meta: [String: AnyCodable]? = nil) {
    params = Params(_meta: _meta)
  }
}
