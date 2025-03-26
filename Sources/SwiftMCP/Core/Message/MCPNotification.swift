import Foundation

// MARK: - MCPNotification

/// Protocol for notification messages
public protocol MCPNotification: MCPMessage {
  associatedtype Params: Codable = EmptyParams
  /// The method name for this notification
  var method: String { get }

  /// The parameters for this notification, if any
  var params: Params { get }
}

extension MCPNotification {
  public var params: EmptyParams { EmptyParams() }
}
