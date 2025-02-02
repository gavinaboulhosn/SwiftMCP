import Foundation

// MARK: - TransportConfiguration

/// Defines overall transport behavior and retry policies.
public struct TransportConfiguration {

  // MARK: Lifecycle

  /// Initializes a transport configuration.

  /// - Parameters:
  /// - connectTimeout: Max time allowed to establish a connection
  /// - sendTimeout: Max time allowed to send a message
  /// - maxMessageSize: Limit in bytes for message size
  /// - retryPolicy: Policy for short-lived operation retries
  /// - healthCheckEnabled: Whether or not to run periodic health checks
  /// - healthCheckInterval: Interval in seconds between health checks
  /// - maxReconnectAttempts: Max attempts to reconnect on health check failures
  public init(
    connectTimeout: TimeInterval = 120.0,
    sendTimeout: TimeInterval = 1200.0,
    maxMessageSize: Int = 4_194_304, // 4 MB
    retryPolicy: TransportRetryPolicy = .default,
    healthCheckEnabled: Bool = false,
    healthCheckInterval: TimeInterval = 30.0,
    maxReconnectAttempts: Int = 3)
  {
    self.connectTimeout = connectTimeout
    self.sendTimeout = sendTimeout
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

// MARK: - TransportRetryPolicy

/// Policy for retrying short-lived operations (e.g. POST calls).
public struct TransportRetryPolicy {

  // MARK: Lifecycle

  /// Creates a retry policy.
  public init(
    maxAttempts: Int = 3,
    baseDelay: TimeInterval = 1.0,
    maxDelay: TimeInterval = 30.0,
    jitter: Double = 0.1,
    backoffPolicy: BackoffPolicy = .exponential)
  {
    self.maxAttempts = maxAttempts
    self.baseDelay = baseDelay
    self.maxDelay = maxDelay
    self.jitter = jitter
    self.backoffPolicy = backoffPolicy
  }

  // MARK: Public

  /// Types of backoff expansions for subsequent retries.
  public enum BackoffPolicy {
    case constant
    case exponential
    case linear
    case custom((Int) -> TimeInterval)

    // MARK: Internal

    func delay(attempt: Int, baseDelay: TimeInterval, jitter: Double) -> TimeInterval {
      let rawDelay: TimeInterval =
        switch self {
        case .constant:
          baseDelay
        case .exponential:
          baseDelay * pow(2.0, Double(attempt - 1))
        case .linear:
          baseDelay * Double(attempt)
        case .custom(let calculator):
          calculator(attempt)
        }
      // Add optional jitter
      if jitter > 0 {
        let jitterRange = rawDelay * jitter
        let randomJitter = Double.random(in: -jitterRange...jitterRange)
        return max(0, rawDelay + randomJitter)
      }
      return rawDelay
    }
  }

  public static let `default` = TransportRetryPolicy()

  /// Maximum number of retry attempts
  public let maxAttempts: Int
  /// Base delay between attempts
  public var baseDelay: TimeInterval
  /// Maximum possible delay
  public var maxDelay: TimeInterval
  /// Jitter factor (0.0 - 1.0)
  public var jitter: Double
  /// Type of backoff policy
  public var backoffPolicy: BackoffPolicy

  /// Calculates the appropriate delay (seconds) for a given attempt number.
  public func delay(forAttempt attempt: Int) -> TimeInterval {
    let raw = backoffPolicy.delay(attempt: attempt, baseDelay: baseDelay, jitter: jitter)
    return min(raw, maxDelay)
  }
}
