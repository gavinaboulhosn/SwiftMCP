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

// MARK: - TransportRetryPolicy

/// Policy for retrying short-lived operations (e.g. POST calls).
public struct TransportRetryPolicy: Codable {

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
  public enum BackoffPolicy: Codable {
    case constant
    case exponential
    case linear
    //    case custom((Int) -> TimeInterval)

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
        @unknown default:
          0
          //        case .custom(let calculator):
          //          calculator(attempt)
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
