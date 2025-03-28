import Foundation

/// Protocol defining the URLSession interface needed by StreamableHTTPTransport.
/// This allows for easier testing by mocking the network layer.
public protocol URLSessionProtocol {
    func data(
        for request: URLRequest,
        delegate: URLSessionTaskDelegate?
    ) async throws -> (Data, URLResponse)

    func bytes(
        for request: URLRequest,
        delegate: URLSessionTaskDelegate?
    ) async throws -> (URLSession.AsyncBytes, URLResponse)
}

extension URLSession: URLSessionProtocol {}
