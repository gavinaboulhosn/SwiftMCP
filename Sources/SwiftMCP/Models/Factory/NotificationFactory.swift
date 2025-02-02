import Foundation

enum NotificationFactory {
  static func makeNotification(
    method: String,
    params: [String: AnyCodable]?)
    -> (any MCPNotification)?
  {
    switch method {
    case CancelledNotification.method:
      if let params = decodeParams(CancelledNotification.Params.self, from: params) {
        return CancelledNotification(requestId: params.requestId, reason: params.reason)
      }

    case InitializedNotification.method:
      if let params = decodeParams(InitializedNotification.Params.self, from: params) {
        return InitializedNotification(_meta: params._meta)
      } else {
        return InitializedNotification()
      }

    case ProgressNotification.method:
      if let params = decodeParams(ProgressNotification.Params.self, from: params) {
        return ProgressNotification(
          progress: params.progress, progressToken: params.progressToken,
          total: params.total)
      }

    case RootsListChangedNotification.method:
      if let params = decodeParams(RootsListChangedNotification.Params.self, from: params) {
        return RootsListChangedNotification(_meta: params._meta)
      } else {
        return RootsListChangedNotification()
      }

    case ResourceListChangedNotification.method:
      if
        let params = decodeParams(
          ResourceListChangedNotification.Params.self,
          from: params)
      {
        return ResourceListChangedNotification(_meta: params._meta)
      } else {
        return ResourceListChangedNotification()
      }

    case ResourceUpdatedNotification.method:
      if let params = decodeParams(ResourceUpdatedNotification.Params.self, from: params) {
        return ResourceUpdatedNotification(uri: params.uri)
      }

    case PromptListChangedNotification.method:
      if let params = decodeParams(PromptListChangedNotification.Params.self, from: params) {
        return PromptListChangedNotification(_meta: params._meta)
      } else {
        return PromptListChangedNotification()
      }

    case ToolListChangedNotification.method:
      if let params = decodeParams(ToolListChangedNotification.Params.self, from: params) {
        return ToolListChangedNotification(_meta: params._meta)
      } else {
        return ToolListChangedNotification()
      }

    case LoggingMessageNotification.method:
      if let params = decodeParams(LoggingMessageNotification.Params.self, from: params) {
        return LoggingMessageNotification(
          data: params.data.value, level: params.level, logger: params.logger)
      }

    default:
      return nil
    }

    return nil
  }
}
