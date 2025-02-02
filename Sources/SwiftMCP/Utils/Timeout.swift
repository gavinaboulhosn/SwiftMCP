import Foundation

// MARK: - TimedOutError

// kudos https://forums.swift.org/t/running-an-async-task-with-a-timeout/49733/38

/// Based on: https://forums.swift.org/t/running-an-async-task-with-a-timeout/49733/21
struct TimedOutError: Error, Equatable { }

/// Execute an operation in the current task subject to a timeout.
///
/// - Parameters:
///   - timeout: The time duration in which `operation` is allowed to run before timing out.
///   - tolerance: The time duriation that is allowed for task scheduler to delay operation timeout
///   in case of computationaly sparse resource.
///   - clock: The clock which is suitable for task scheduling.
///   - operation: The asynchronous operation to perform.
/// - Returns: The result of `operation` if it completed in time.
/// - Throws: Throws ``TimedOutError`` if the timeout expires before `operation` completes.
///   If `operation` throws an error before the timeout expires, that error is propagated to the caller.
func with<Return: Sendable, C: Clock>(
  timeout: C.Instant.Duration,
  tolerance: C.Instant.Duration? = nil,
  clock: C,
  operation: @escaping @Sendable () async throws -> Return)
  async rethrows -> Return
{
  try await withThrowingTaskGroup(of: Return.self) { group in
    let expiration = C.Instant.now.advanced(by: timeout)
    defer {
      group.cancelAll() // cancel the other task
    }
    group.addTask {
      try await Task.sleep(
        until: expiration,
        tolerance: tolerance,
        clock: clock) // sleep supports cancellation
      throw TimedOutError() // timeout has been reached
    }
    group.addTask {
      try await operation()
    }
    // first finished child task wins
    return try await group.next()! // never fails
  }
}

/// Execute an operation in the current task subject to a timeout with continuous clock
/// suitable for realtime task scheduling.
///
/// - Parameters:
///   - timeout: The time duration in which `operation` is allowed to run before timing out.
///   - tolerance: The time duriation that is allowed for task scheduler to delay operation timeout
///   in case of computationaly sparse resource.
///   - operation: The asynchronous operation to perform.
/// - Returns: The result of `operation` if it completed in time.
/// - Throws: Throws ``TimedOutError`` if the timeout expires before `operation` completes.
///   If `operation` throws an error before the timeout expires, that error is propagated to the caller.
func with<Return: Sendable>(
  timeout: ContinuousClock.Instant.Duration,
  tolerance: ContinuousClock.Instant.Duration? = nil,
  operation: @escaping @Sendable () async throws -> Return)
  async rethrows -> Return
{
  try await with(
    timeout: timeout,
    tolerance: tolerance,
    clock: .continuous,
    operation: operation)
}

extension InstantProtocol {
  fileprivate static var now: Self {
    switch Self.self {
    case is ContinuousClock.Instant.Type:
      ContinuousClock.Instant.now as! Self
    case is SuspendingClock.Instant.Type:
      SuspendingClock.Instant.now as! Self
    default:
      fatalError("Not implemented")
    }
  }
}
