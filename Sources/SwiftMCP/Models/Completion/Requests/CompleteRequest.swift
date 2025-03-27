import Foundation

public struct CompleteRequest: MCPRequest {
  public typealias Response = CompleteResult

  public struct Params: MCPRequestParams {
    public var _meta: RequestMeta?
    public let argument: CompletionArgument
    public let ref: CompletionReference
  }

  public static let method = "completion/complete"
  public var params: Params

  public init(argument: CompletionArgument, ref: CompletionReference) {
    params = Params(argument: argument, ref: ref)
  }
}
