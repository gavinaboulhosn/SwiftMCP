import Foundation

public enum LoggingLevel: String, Codable, Sendable {
    case alert, critical, debug, emergency, error, info, notice, warning
}

public struct SetLevelRequest: MCPRequest {
    public static let method = "logging/setLevel"
    public typealias Response = EmptyResult

    public struct Params: MCPRequestParams {
        public var _meta: RequestMeta?
        public let level: LoggingLevel
    }

    public var params: Params

    public init(level: LoggingLevel) {
        self.params = Params(level: level)
    }
    /// Empty result since just a confirmation is needed.
    public struct EmptyResult: MCPResponse {
        public typealias Request = SetLevelRequest
        public var _meta: [String: AnyCodable]?
    }
}

public struct LoggingMessageNotification: MCPNotification {
    public static let method = "notifications/message"

    public struct Params: Codable, Sendable {
        public let data: AnyCodable
        public let level: LoggingLevel
        public let logger: String?
    }

    public var params: Params

    public init(data: Any, level: LoggingLevel, logger: String? = nil) {
        self.params = Params(data: AnyCodable(data), level: level, logger: logger)
    }
}
