import Foundation

// MARK: - TransportConfiguration

extension TransportConfiguration {
  public static let dummyData = TransportConfiguration.default
}

/// Defines overall transport behavior and retry policies.
public struct TransportConfiguration: Codable {

  // MARK: Lifecycle

  /// Initializes a transport configuration.
  /// - Parameters:
  ///   - connectTimeout: Max time allowed to establish a connection
  ///   - sendTimeout: Max time spent on the "send" operation
  ///   - requestTimeout: Max time spent by client for request
  ///   - responseTimeout: Max time given to server to respond
  ///   - maxMessageSize: Limit in bytes for message size
  ///   - retryPolicy: Policy for short-lived operation retries
  ///   - healthCheckEnabled: Whether or not to run periodic health checks
  ///   - healthCheckInterval: Interval in seconds between health checks
  ///   - maxReconnectAttempts: Max attempts to reconnect on health check failures
  public init(
    connectTimeout: TimeInterval = 30.0,
    sendTimeout: TimeInterval = 30.0,
    requestTimeout: TimeInterval = 60.0,
    responseTimeout: TimeInterval = 60.0,
    maxMessageSize: Int = 4_194_304, // 4 MB
    retryPolicy: TransportRetryPolicy = .default,
    healthCheckEnabled: Bool = true,
    healthCheckInterval: TimeInterval = 30.0,
    maxReconnectAttempts: Int = 3)
  {
    self.connectTimeout = connectTimeout
    self.sendTimeout = sendTimeout
    self.requestTimeout = requestTimeout
    self.responseTimeout = responseTimeout
    self.maxMessageSize = maxMessageSize
    self.retryPolicy = retryPolicy
    self.healthCheckEnabled = healthCheckEnabled
    self.healthCheckInterval = healthCheckInterval
    self.maxReconnectAttempts = maxReconnectAttempts
  }

  // MARK: Public

  public static let `default` = TransportConfiguration()

  /// Maximum time to wait for connection in seconds
  public var connectTimeout: TimeInterval
  /// Maximum time to wait for sending data in seconds
  public var sendTimeout: TimeInterval
  /// Timeout on client side before failing a request in seconds
  public var requestTimeout: TimeInterval
  /// Max time server is given to respond in seconds
  public var responseTimeout: TimeInterval
  /// Maximum allowed message size in bytes
  public var maxMessageSize: Int
  /// Retry policy for short-lived operations
  public var retryPolicy: TransportRetryPolicy

  // MARK: - Health Checks & Reconnection

  /// Enables client-side health checks if `true`
  public var healthCheckEnabled: Bool
  /// Interval (seconds) between health checks
  public var healthCheckInterval: TimeInterval
  /// Maximum reconnection attempts when health checks fail
  public var maxReconnectAttempts: Int

}
