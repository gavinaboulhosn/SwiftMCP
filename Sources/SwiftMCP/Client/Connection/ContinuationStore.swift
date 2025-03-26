import Foundation

/// Actor to manage continuations safely
actor ContinuationStore {

  // MARK: Internal

  func store(_ id: UUID, _ continuation: AsyncStream<ConnectionStateEvent>.Continuation) {
    continuations[id] = continuation
  }

  func remove(_ id: UUID) {
    continuations.removeValue(forKey: id)
  }

  func yieldToAll(_ event: ConnectionStateEvent) {
    for continuation in continuations.values {
      continuation.yield(event)
    }
  }

  // MARK: Private

  private var continuations: [UUID: AsyncStream<ConnectionStateEvent>.Continuation] = [:]
}
