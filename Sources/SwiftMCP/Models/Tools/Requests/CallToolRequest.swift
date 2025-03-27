import Foundation

/// Used by the client to invoke a tool provided by the server.
///
/// Defined in MCP spec under the "CallToolRequest" definition:
/// ```json
/// {
///   "description": "Used by the client to invoke a tool provided by the server.",
///   "properties": {
///     "method": {
///       "const": "tools/call",
///       "type": "string"
///     },
///     "params": {
///       "properties": {
///         "arguments": {
///           "additionalProperties": {},
///           "type": "object"
///         },
///         "name": {
///           "type": "string"
///         }
///       },
///       "required": ["name"],
///       "type": "object"
///     }
///   }
/// }
/// ```
public struct CallToolRequest: MCPRequest {
    public static let method = "tools/call"
    public typealias Response = CallToolResult

    public struct Params: MCPRequestParams {
        public var _meta: RequestMeta?
        public let name: String
        public let arguments: [String: AnyCodable]

        public init(name: String, arguments: [String: AnyCodable]?) {
            self.name = name
            self.arguments = arguments ?? [:]
        }
    }

    public var params: Params

    public init(name: String, arguments: [String: Any]? = nil) {
        params = Params(name: name, arguments: arguments?.mapValues(AnyCodable.init))
    }
}
