import Foundation

public struct CompleteResult: MCPResponse {
  public typealias Request = CompleteRequest

  public let completion: CompletionResult
  public var _meta: [String: AnyCodable]?

  public init(completion: CompletionResult, meta: [String: AnyCodable]? = nil) {
    self.completion = completion
    _meta = meta
  }
}
