import Foundation

/// Policy for retrying short-lived operations (e.g. POST calls).
public struct TransportRetryPolicy: Codable, Equatable {

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
  public enum BackoffPolicy: Codable, Equatable {
    case constant
    case exponential
    case linear

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

  // MARK: - Equatable

  public static func == (lhs: TransportRetryPolicy, rhs: TransportRetryPolicy) -> Bool {
    lhs.maxAttempts == rhs.maxAttempts &&
    lhs.baseDelay == rhs.baseDelay &&
    lhs.maxDelay == rhs.maxDelay &&
    lhs.jitter == rhs.jitter &&
    lhs.backoffPolicy == rhs.backoffPolicy
  }
}
