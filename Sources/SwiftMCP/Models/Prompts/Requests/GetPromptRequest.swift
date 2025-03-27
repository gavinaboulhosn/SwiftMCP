import Foundation

/// Used by the client to get a prompt provided by the server.
///
/// MCP Schema:
/// ```json
/// {
///   "description": "Used by the client to get a prompt provided by the server.",
///   "properties": {
///     "method": {
///       "const": "prompts/get",
///       "type": "string"
///     },
///     "params": {
///       "properties": {
///         "name": {
///           "description": "The name of the prompt or prompt template.",
///           "type": "string"
///         },
///         "arguments": {
///           "description": "Arguments to use for templating the prompt.",
///           "additionalProperties": {
///             "type": "string"
///           },
///           "type": "object"
///         }
///       },
///       "required": ["name"],
///       "type": "object"
///     }
///   },
///   "required": ["method", "params"],
///   "type": "object"
/// }
/// ```
public struct GetPromptRequest: MCPRequest, Sendable {
  public static let method = "prompts/get"
  public typealias Response = GetPromptResult

  public struct Params: MCPRequestParams, Sendable {
    public var _meta: RequestMeta?

    /// The name of the prompt or prompt template.
    public let name: String

    /// Arguments to use for templating the prompt.
    public let arguments: [String: String]?
  }

  public var params: Params

  public init(name: String, arguments: [String: String]? = nil) {
    params = Params(name: name, arguments: arguments)
  }
}
