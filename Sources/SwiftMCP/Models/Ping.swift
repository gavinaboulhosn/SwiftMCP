import Foundation

public struct PingRequest: MCPRequest {
  public var params = EmptyParams()

  public static let method = "ping"
  public typealias Response = EmptyResult

  public init() { }

  public struct EmptyResult: MCPResponse {
    public typealias Request = PingRequest
    public var _meta: [String: AnyCodable]?
  }
}
