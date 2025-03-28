import Foundation
@testable import SwiftMCP
import Testing

@Suite("SSE Parser Tests")
struct SSEParserTests {
    @Test("Basic Message Parsing")
    func testBasicMessageParsing() async throws {
        let parser = SSEParser()

        // Test single data line
        var event = try await parser.parseLine("data: Hello World")
        #expect(event == nil) // No event yet, waiting for empty line

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "message")
        #expect(event?.id == nil)
        #expect(String(data: event!.data, encoding: .utf8) == "Hello World\n")
    }

    @Test("Multi-line Data")
    func testMultilineData() async throws {
        let parser = SSEParser()

        // Send multiple data lines
        var event = try await parser.parseLine("data: Line 1")
        #expect(event == nil)

        event = try await parser.parseLine("data: Line 2")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "message")
        #expect(event?.id == nil)
        #expect(String(data: event!.data, encoding: .utf8) == "Line 1\nLine 2\n")
    }

    @Test("Event Type and ID")
    func testEventTypeAndId() async throws {
        let parser = SSEParser()

        var event = try await parser.parseLine("event: custom")
        #expect(event == nil)

        event = try await parser.parseLine("id: 123")
        #expect(event == nil)

        event = try await parser.parseLine("data: Test Data")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "custom")
        #expect(event?.id == "123")
        #expect(String(data: event!.data, encoding: .utf8) == "Test Data\n")
    }

    @Test("Comments and Unknown Fields")
    func testCommentsAndUnknownFields() async throws {
        let parser = SSEParser()

        // Comments should be ignored
        var event = try await parser.parseLine(": this is a comment")
        #expect(event == nil)

        // Unknown fields should be ignored
        event = try await parser.parseLine("unknown: field")
        #expect(event == nil)

        event = try await parser.parseLine("data: actual data")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(String(data: event!.data, encoding: .utf8) == "actual data\n")
    }

    @Test("Retry Field")
    func testRetryField() async throws {
        let parser = SSEParser()

        // Retry field should be parsed but not affect event
        var event = try await parser.parseLine("retry: 5000")
        #expect(event == nil)

        event = try await parser.parseLine("data: test")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "message")
        #expect(String(data: event!.data, encoding: .utf8) == "test\n")
    }

    @Test("Flush Buffered Data")
    func testFlush() async throws {
        let parser = SSEParser()

        // Add some data without ending the event
        var event = try await parser.parseLine("event: custom")
        #expect(event == nil)

        event = try await parser.parseLine("data: buffered")
        #expect(event == nil)

        // Flush should return the buffered event
        let flushedEvent = await parser.flush()
        #expect(flushedEvent != nil)
        #expect(flushedEvent?.type == "custom")
        #expect(String(data: flushedEvent!.data, encoding: .utf8) == "buffered\n")

        // Buffer should be cleared
        let emptyFlush = await parser.flush()
        #expect(emptyFlush == nil)
    }

    @Test("Reset Parser")
    func testReset() async throws {
        let parser = SSEParser()

        // Add some data
        var event = try await parser.parseLine("event: custom")
        #expect(event == nil)

        event = try await parser.parseLine("data: test")
        #expect(event == nil)

        // Reset the parser
        await parser.reset()

        // Verify state is reset by checking next event is default type
        event = try await parser.parseLine("data: after reset")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "message") // Back to default type
        #expect(String(data: event!.data, encoding: .utf8) == "after reset\n")
    }

    @Test("Whitespace Handling")
    func testWhitespaceHandling() async throws {
        let parser = SSEParser()

        var event = try await parser.parseLine("event:  custom  ")
        #expect(event == nil)

        event = try await parser.parseLine("data:  spaced data  ")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "custom")
        #expect(String(data: event!.data, encoding: .utf8) == "spaced data\n")
    }
}
