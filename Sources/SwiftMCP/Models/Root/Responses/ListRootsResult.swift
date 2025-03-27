import Foundation

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
