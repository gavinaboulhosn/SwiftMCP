import Foundation

// MARK: - Root

/// Root definition
public struct Root: Codable, Sendable, Equatable {
  public let uri: String
  public let name: String?

  public init(uri: String, name: String? = nil) {
    self.uri = uri
    self.name = name
  }
}

// MARK: - ListRootsRequest

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

// MARK: - ListRootsResult

public struct ListRootsResult: MCPResponse {
  public typealias Request = ListRootsRequest

  public var _meta: [String: AnyCodable]?
  public let roots: [Root]

  public init(
    roots: [Root],
    meta: [String: AnyCodable]? = nil)
  {
    self.roots = roots
    _meta = meta
  }
}
