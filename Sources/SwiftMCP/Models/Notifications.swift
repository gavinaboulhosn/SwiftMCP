import Foundation

public typealias ProgressToken = RequestID

extension MCPNotification {
  public static func cancel(requestId: RequestID, reason: String? = nil) -> any MCPNotification {
    CancelledNotification(requestId: requestId, reason: reason)
  }

  public static func initialized(meta: [String: Any]? = nil) -> any MCPNotification {
    InitializedNotification(_meta: meta?.mapValues { AnyCodable($0) })
  }

  public static func progress(
    progress: Double,
    progressToken: ProgressToken,
    total: Double? = nil)
    -> any MCPNotification
  {
    ProgressNotification(progress: progress, progressToken: progressToken, total: total)
  }

  public static func rootsListChanged(meta: [String: Any]? = nil) -> any MCPNotification {
    RootsListChangedNotification(_meta: meta?.mapValues { AnyCodable($0) })
  }

  public static func resourceListChanged(meta: [String: Any]? = nil) -> any MCPNotification {
    ResourceListChangedNotification(_meta: meta?.mapValues { AnyCodable($0) })
  }

  public static func resourceUpdated(uri: String) -> any MCPNotification {
    ResourceUpdatedNotification(uri: uri)
  }

  public static func promptListChanged(meta: [String: Any]? = nil) -> any MCPNotification {
    PromptListChangedNotification(_meta: meta?.mapValues { AnyCodable($0) })
  }

  public static func toolListChanged(meta: [String: Any]? = nil) -> any MCPNotification {
    ToolListChangedNotification(_meta: meta?.mapValues { AnyCodable($0) })
  }

}

public struct CancelledNotification: MCPNotification {
  public static let method = "notifications/cancelled"
  public var method: String { CancelledNotification.method }

  public struct Params: Codable, Sendable {
    public let requestId: RequestID
    public let reason: String?
  }

  public var params: Params

  public init(requestId: RequestID, reason: String? = nil) {
    params = Params(requestId: requestId, reason: reason)
  }
}

public struct InitializedNotification: MCPNotification {
  public static let method = "notifications/initialized"
  public var method: String { InitializedNotification.method }

  public struct Params: Codable, Sendable {
    public let _meta: [String: AnyCodable]?
  }

  public var params: Params

  public init(_meta: [String: AnyCodable]? = nil) {
    params = Params(_meta: _meta)
  }
}

public struct ProgressNotification: MCPNotification {
  public static let method = "notifications/progress"
  public var method: String { ProgressNotification.method }

  public struct Params: Codable, Sendable {
    public let progress: Double
    public let progressToken: ProgressToken
    public let total: Double?
  }

  public var params: Params

  public init(progress: Double, progressToken: ProgressToken, total: Double? = nil) {
    params = Params(
      progress: progress,
      progressToken: progressToken,
      total: total)
  }
}

public struct RootsListChangedNotification: MCPNotification {
  public static let method = "notifications/roots/list_changed"
  public var method: String { RootsListChangedNotification.method }

  public struct Params: Codable, Sendable {
    public let _meta: [String: AnyCodable]?
  }

  public var params: Params

  public init(_meta: [String: AnyCodable]? = nil) {
    params = Params(_meta: _meta)
  }
}

public struct ResourceListChangedNotification: MCPNotification {
  public static let method = "notifications/resources/list_changed"
  public var method: String { ResourceListChangedNotification.method }

  public struct Params: Codable, Sendable {
    public let _meta: [String: AnyCodable]?
  }

  public var params: Params

  public init(_meta: [String: AnyCodable]? = nil) {
    params = Params(_meta: _meta)
  }
}

public struct ResourceUpdatedNotification: MCPNotification {
  public static let method = "notifications/resources/updated"
  public var method: String { ResourceUpdatedNotification.method }

  public struct Params: Codable, Sendable {
    public let uri: String
  }

  public var params: Params

  public init(uri: String) {
    params = Params(uri: uri)
  }
}

public struct PromptListChangedNotification: MCPNotification {
  public static let method = "notifications/prompts/list_changed"
  public var method: String { PromptListChangedNotification.method }

  public struct Params: Codable, Sendable {
    public let _meta: [String: AnyCodable]?
  }

  public var params: Params

  public init(_meta: [String: AnyCodable]? = nil) {
    params = Params(_meta: _meta)
  }
}

public struct ToolListChangedNotification: MCPNotification {
  public static let method = "notifications/tools/list_changed"
  public var method: String { ToolListChangedNotification.method }

  public struct Params: Codable, Sendable {
    public let _meta: [String: AnyCodable]?
  }

  public var params: Params

  public init(_meta: [String: AnyCodable]? = nil) {
    params = Params(_meta: _meta)
  }
}

// MARK: - LoggingMessageNotification

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

// MARK: - AnyMCPNotification

public struct AnyMCPNotification: MCPNotification {
  public var method: String
  public var params: [String: AnyCodable]?

  public init(method: String, params: [String: AnyCodable]?) {
    self.method = method
    self.params = params
  }
}
