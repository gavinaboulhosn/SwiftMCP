import Foundation

// MARK: - PendingRequestProtocol

/// Protocol for representing pending requests with common operations
protocol PendingRequestProtocol {
  func cancel(with error: Error)
  func complete(with response: any MCPResponse) throws

  var responseType: any MCPResponse.Type { get }
  var message: JSONRPCMessage { get }
}

// MARK: - PendingRequest

/// Concrete implementation of pending request with typed response
struct PendingRequest<Response: MCPResponse>: PendingRequestProtocol {
  let message: JSONRPCMessage
  let continuation: CheckedContinuation<Response, any Error>
  let timeoutTask: Task<Void, Never>?

  var responseType: any MCPResponse.Type { Response.self }

  func cancel(with error: Error) {
    timeoutTask?.cancel()
    continuation.resume(throwing: error)
  }

  func complete(with response: any MCPResponse) throws {
    guard let typedResponse = response as? Response else {
      throw MCPError.internalError("Unexpected response type")
    }
    timeoutTask?.cancel()
    continuation.resume(returning: typedResponse)
  }
}
