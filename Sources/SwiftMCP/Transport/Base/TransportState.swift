import Foundation

// MARK: - TransportState

/// Represents the high-level connection state of a transport.
public enum TransportState {
  /// Transport is not connected
  case disconnected
  /// Transport is in the process of connecting
  case connecting
  /// Transport is connected
  case connected
  /// Transport has failed
  case failed(Error)
}

// MARK: CustomStringConvertible, CustomDebugStringConvertible

/// Conformance for printing or debugging `TransportState`.
extension TransportState: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    switch self {
    case .disconnected: "disconnected"
    case .connecting: "connecting"
    case .connected: "connected"
    case .failed(let error): "failed: \(error)"
    }
  }

  public var debugDescription: String { description }
}

// MARK: Equatable

extension TransportState: Equatable {
  public static func ==(lhs: TransportState, rhs: TransportState) -> Bool {
    switch (lhs, rhs) {
    case (.disconnected, .disconnected),
         (.connecting, .connecting),
         (.connected, .connected),
         (.failed, .failed):
      true
    default:
      false
    }
  }
}
