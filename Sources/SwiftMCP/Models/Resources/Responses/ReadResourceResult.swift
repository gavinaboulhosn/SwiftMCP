import Foundation

public struct ReadResourceResult: MCPResponse {
  public typealias Request = ReadResourceRequest

  public var _meta: [String: AnyCodable]?
  public let contents: [ResourceContentsVariant]
}
