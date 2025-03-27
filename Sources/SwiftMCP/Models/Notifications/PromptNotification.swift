import Foundation

public struct PromptListChangedNotification: MCPNotification {
  public static let method = "notifications/prompts/list_changed"
  public var method: String { PromptListChangedNotification.method }

  public struct Params: Codable, Sendable {
    public let _meta: [String: AnyCodable]?
  }

  public var params: Params

  public init(_meta: [String: AnyCodable]? = nil) {
    params = Params(_meta: _meta)
  }
}
