import Foundation

// MARK: - RetryableTransport

/// A protocol for transports to optionally provide a `withRetry` API.
public protocol RetryableTransport: MCPTransport {
  func withRetry<T>(
    operation: String,
    block: @escaping () async throws -> T) async throws -> T
}

/// Default implementation of `withRetry`.
extension RetryableTransport {
  public func withRetry<T>(
    operation _: String,
    block: @escaping () async throws -> T)
    async throws -> T
  {
    var attempt = 1
    var lastError: Error?

    while attempt <= configuration.retryPolicy.maxAttempts {
      do {
        return try await block()
      } catch {
        lastError = error
        // If we've used all attempts, stop
        guard attempt < configuration.retryPolicy.maxAttempts else { break }

        let delay = configuration.retryPolicy.delay(forAttempt: attempt)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        attempt += 1
      }
    }
    throw TransportError.operationFailed("\(String(describing: lastError))")
  }
}
