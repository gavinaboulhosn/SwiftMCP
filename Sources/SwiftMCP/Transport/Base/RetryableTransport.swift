import Foundation

// MARK: - RetryableTransport

/// A protocol for transports to optionally provide a `withRetry` API.
public protocol RetryableTransport: MCPTransport {
  func withRetry<T>(
    operation: String,
    block: @escaping () async throws -> T
  ) async throws -> T
}

/// Default implementation of `withRetry`.
extension RetryableTransport {
  public func withRetry<T>(
    operation: String,
    block: @escaping () async throws -> T
  ) async throws -> T {
    var attempt = 1
    let maxAttempts = configuration.retryPolicy.maxAttempts
    var lastError: Error?

    while attempt <= maxAttempts {
      do {
        return try await block()
      } catch {
        lastError = error
        guard attempt < maxAttempts else { break }
        let delay = configuration.retryPolicy.delay(forAttempt: attempt)
        try await Task.sleep(for: .seconds(delay))
        attempt += 1
      }
    }

    throw TransportError.operationFailed(
      "\(operation) failed after \(maxAttempts) attempts: \(String(describing: lastError))"
    )
  }
}
