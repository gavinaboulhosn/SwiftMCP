import Foundation

public struct AnyMCPNotification: MCPNotification {
  public var method: String
  public var params: [String: AnyCodable]?

  public init(method: String, params: [String: AnyCodable]?) {
    self.method = method
    self.params = params
  }
}
