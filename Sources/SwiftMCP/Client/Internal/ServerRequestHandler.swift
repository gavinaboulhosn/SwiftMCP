import Foundation

/// Type definition for a function that handles incoming server requests
public typealias ServerRequestHandler = (any MCPRequest) async throws -> any MCPResponse
