import Foundation

public struct LoggingMessageNotification: MCPNotification {
  public static let method = "notifications/message"
  public var method: String { LoggingMessageNotification.method }

  public struct Params: Codable, Sendable {
    public let data: AnyCodable
    public let level: LoggingLevel
    public let logger: String?
  }

  public var params: Params

  public init(data: Any, level: LoggingLevel, logger: String? = nil) {
    params = Params(data: AnyCodable(data), level: level, logger: logger)
  }
}
