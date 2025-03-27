import Foundation

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
