import Foundation

public struct UnsubscribeRequest: MCPRequest {
  public static var method = "resources/unsubscribe"
  public typealias Response = EmptyResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let uri: String
  }

  public var params: Params

  public init(uri: String) {
    params = Params(uri: uri)
  }

  public struct EmptyResult: MCPResponse {
    public typealias Request = UnsubscribeRequest
    public var _meta: [String: AnyCodable]?
  }
}
