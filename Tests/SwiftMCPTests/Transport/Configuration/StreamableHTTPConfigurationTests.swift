import Foundation
@testable import SwiftMCP
import Testing

@Suite("StreamableHTTPConfiguration Tests")
struct StreamableHTTPConfigurationTests {
    @Test("Initialization with default values")
    func testDefaultInitialization() throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        let config = StreamableHTTPConfiguration(endpoint: endpoint)

        #expect(config.endpoint == endpoint)
        #expect(config.headers.isEmpty)
        #expect(config.transport == .default)
        #expect(config.validateCertificates == true)
        #expect(config.autoResumeStreams == true)
        #expect(config.maxSimultaneousStreams == 4)
    }

    @Test("Initialization with custom values")
    func testCustomInitialization() throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        let headers = ["Custom-Header": "Value"]
        let transport = TransportConfiguration(connectTimeout: 60.0)

        let config = StreamableHTTPConfiguration(
            endpoint: endpoint,
            headers: headers,
            transport: transport,
            validateCertificates: false,
            autoResumeStreams: false,
            maxSimultaneousStreams: 2
        )

        #expect(config.endpoint == endpoint)
        #expect(config.headers == headers)
        #expect(config.transport.connectTimeout == 60.0)
        #expect(config.validateCertificates == false)
        #expect(config.autoResumeStreams == false)
        #expect(config.maxSimultaneousStreams == 2)
    }

    @Test("Default headers include required Accept and Content-Type")
    func testDefaultHeaders() throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        let config = StreamableHTTPConfiguration(endpoint: endpoint)
        let headers = config.defaultHeaders

        #expect(headers["Accept"] == "application/json, text/event-stream")
        #expect(headers["Content-Type"] == "application/json")
    }

    @Test("SSE headers include text/event-stream Accept")
    func testSSEHeaders() throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        let config = StreamableHTTPConfiguration(endpoint: endpoint)
        let headers = config.sseHeaders

        #expect(headers["Accept"] == "text/event-stream")
    }

    @Test("Custom headers are preserved in default headers")
    func testCustomHeadersPreserved() throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        let customHeaders = ["Custom-Header": "Value"]
        let config = StreamableHTTPConfiguration(endpoint: endpoint, headers: customHeaders)
        let headers = config.defaultHeaders

        #expect(headers["Custom-Header"] == "Value")
        #expect(headers["Accept"] == "application/json, text/event-stream")
        #expect(headers["Content-Type"] == "application/json")
    }

    @Test("URLSession configuration reflects transport settings")
    func testURLSessionConfiguration() throws {
        let endpoint = URL(string: "https://example.com/mcp")!
        let transport = TransportConfiguration(
            requestTimeout: 45.0,
            responseTimeout: 90.0
        )
        let config = StreamableHTTPConfiguration(
            endpoint: endpoint,
            transport: transport,
            validateCertificates: false
        )

        let sessionConfig = config.urlSessionConfiguration

        #expect(sessionConfig.timeoutIntervalForRequest == 45.0)
        #expect(sessionConfig.timeoutIntervalForResource == 90.0)
        #expect(sessionConfig.tlsMinimumSupportedProtocolVersion == .TLSv12)
        #expect(sessionConfig.tlsMaximumSupportedProtocolVersion == .TLSv13)
        #expect(sessionConfig.httpAdditionalHeaders?["Accept"] as? String == "application/json, text/event-stream")
        #expect(sessionConfig.httpAdditionalHeaders?["Content-Type"] as? String == "application/json")
    }
}
