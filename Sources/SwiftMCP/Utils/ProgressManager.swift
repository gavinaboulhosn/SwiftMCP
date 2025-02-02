import Foundation

// MARK: - ProgressHandler

public struct ProgressHandler {
  public typealias UpdateHandler = @Sendable (Double, Double?) -> Void

  private let handler: UpdateHandler?
  private let token: ProgressToken

  init(token: ProgressToken, handler: UpdateHandler?) {
    self.token = token
    self.handler = handler
  }

  func handle(_ notification: ProgressNotification) {
    guard let handler, notification.params.progressToken == token else { return }
    handler(notification.params.progress, notification.params.total)
  }
}

// MARK: - ProgressManager

actor ProgressManager {

  // MARK: Internal

  func register(_ handler: ProgressHandler?, for token: ProgressToken) {
    guard let handler else {
      handlers[token] = nil
      return
    }
    handlers[token] = handler
  }

  func unregister(for token: ProgressToken) {
    handlers[token] = nil
  }

  func handle(_ notification: ProgressNotification) {
    guard let handler = handlers[notification.params.progressToken]
    else { return }
    handler.handle(notification)
  }

  // MARK: Private

  private var handlers: [ProgressToken: ProgressHandler] = [:]

}
