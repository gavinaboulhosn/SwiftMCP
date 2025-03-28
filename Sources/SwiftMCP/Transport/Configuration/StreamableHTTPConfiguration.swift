import Foundation

/// Configuration for the Streamable HTTP transport.
public struct StreamableHTTPConfiguration {
    // MARK: - Properties

    /// The MCP endpoint URL that supports both POST and GET methods
    public let endpoint: URL

    /// Additional headers to include in requests
    public let headers: [String: String]

    /// Base transport configuration
    public let transport: TransportConfiguration

    /// Whether to validate TLS certificates
    public let validateCertificates: Bool

    /// Whether to automatically resume SSE streams on disconnection
    public let autoResumeStreams: Bool

    /// Maximum number of simultaneous SSE streams
    public let maxSimultaneousStreams: Int

    // MARK: - Initialization

    /// Creates a new StreamableHTTPConfiguration
    /// - Parameters:
    ///   - endpoint: The MCP endpoint URL
    ///   - headers: Additional headers to include in requests
    ///   - transport: Base transport configuration
    ///   - validateCertificates: Whether to validate TLS certificates
    ///   - autoResumeStreams: Whether to automatically resume SSE streams
    ///   - maxSimultaneousStreams: Maximum number of simultaneous SSE streams
    public init(
        endpoint: URL,
        headers: [String: String] = [:],
        transport: TransportConfiguration = .default,
        validateCertificates: Bool = true,
        autoResumeStreams: Bool = true,
        maxSimultaneousStreams: Int = 4
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.transport = transport
        self.validateCertificates = validateCertificates
        self.autoResumeStreams = autoResumeStreams
        self.maxSimultaneousStreams = maxSimultaneousStreams
    }

    // MARK: - Default Headers

    /// Returns headers that should be included in all requests
    var defaultHeaders: [String: String] {
        var headers = self.headers

        // Required Accept header for all requests
        headers["Accept"] = "application/json, text/event-stream"

        // Content-Type for POST requests
        headers["Content-Type"] = "application/json"

        return headers
    }

    /// Returns headers specifically for SSE requests
    var sseHeaders: [String: String] {
        var headers = self.headers
        headers["Accept"] = "text/event-stream"
        return headers
    }
}

// MARK: - URLSession Configuration

extension StreamableHTTPConfiguration {
    /// Creates a URLSession configuration based on the transport settings
    var urlSessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default

        // Set timeouts
        config.timeoutIntervalForRequest = transport.requestTimeout
        config.timeoutIntervalForResource = transport.responseTimeout

        // Configure TLS validation
        if !validateCertificates {
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
            config.tlsMaximumSupportedProtocolVersion = .TLSv13
        }

        // Add default headers
        config.httpAdditionalHeaders = defaultHeaders

        return config
    }
}
