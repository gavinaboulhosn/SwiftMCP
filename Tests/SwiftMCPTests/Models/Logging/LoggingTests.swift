import Foundation
import Testing

@testable import SwiftMCP

@Suite("Logging Tests")
struct LoggingTests {
    @Test("LoggingLevel Encoding/Decoding")
    func testLoggingLevelCoding() throws {
        let levels: [LoggingLevel] = [
            .alert, .critical, .debug, .emergency,
            .error, .info, .notice, .warning
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for level in levels {
            let encoded = try encoder.encode(level)
            let decoded = try decoder.decode(LoggingLevel.self, from: encoded)
            #expect(decoded == level)
        }
    }

    @Test("SetLevelRequest Encoding/Decoding")
    func testSetLevelRequest() throws {
        let expectedJSON = """
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "logging/setLevel",
          "params": {
            "level": "debug"
          }
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(JSONRPCMessage.self, from: expectedJSON)
        guard case .request(let id, let req) = message else {
            Issue.record("Expected a request message")
            return
        }

        #expect(id == .int(1))

        let params = req.params as? SetLevelRequest.Params
        if let params = params {
            #expect(params.level == .debug)
        } else {
            Issue.record("params is nil, expected level parameter")
        }

        // Test encoding
        let request = SetLevelRequest(level: .debug)
        let encoded = try JSONEncoder().encode(request)
        let decodedRequest = try JSONDecoder().decode(SetLevelRequest.self, from: encoded)
        #expect(decodedRequest.params.level == .debug)
    }

    @Test("SetLevelRequest Empty Result")
    func testSetLevelEmptyResult() throws {
        let emptyResult = SetLevelRequest.EmptyResult()
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(emptyResult)
        let decoded = try JSONDecoder().decode(SetLevelRequest.EmptyResult.self, from: encoded)
        #expect(decoded._meta == nil)
    }
}
