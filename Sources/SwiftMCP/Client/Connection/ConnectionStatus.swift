import Foundation

/// Represents the overall connection status from a high-level perspective.
public enum ConnectionStatus: Equatable, Sendable {
  case connected
  case connecting
  case disconnected
  case failed(Error)

  // MARK: Public

  public var hasError: Bool {
    switch self {
    case .failed:
      return true
    default:
      return false
    }
  }

  public static func ==(lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
    switch (lhs, rhs) {
    case (.connected, .connected),
         (.connecting, .connecting),
         (.disconnected, .disconnected),
         (.failed, .failed):
      true
    default:
      false
    }
  }
}
