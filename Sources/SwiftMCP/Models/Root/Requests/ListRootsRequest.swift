import Foundation

public struct ListRootsRequest: MCPRequest {
  public static var method = "roots/list"
  public typealias Response = ListRootsResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
  }

  public var params: Params

  public init(meta: RequestMeta? = nil) {
    params = Params(_meta: meta)
  }
}
