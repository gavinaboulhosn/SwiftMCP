import Foundation
@testable import SwiftMCP
import Testing

@Suite("SSE Parser Tests")
struct SSEParserTests {
    @Test("Basic Message Parsing")
    func testBasicMessageParsing() async throws {
        let parser = SSEParser()

        // Test single data line
        var event = try await parser.parseLine("data:Hello World")
        #expect(event == nil) // No event yet, waiting for empty line

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "message")
        #expect(event?.id == nil)
        #expect(String(data: event!.data, encoding: .utf8) == "Hello World")
    }

    @Test("Multi-line Data")
    func testMultilineData() async throws {
        let parser = SSEParser()

        // Send multiple data lines
        var event = try await parser.parseLine("data:Line 1")
        #expect(event == nil)

        event = try await parser.parseLine("data:Line 2")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "message")
        #expect(event?.id == nil)
        #expect(String(data: event!.data, encoding: .utf8) == "Line 1\nLine 2")
    }

    @Test("Event Type and ID")
    func testEventTypeAndId() async throws {
        let parser = SSEParser()

        var event = try await parser.parseLine("event: custom")
        #expect(event == nil)

        event = try await parser.parseLine("id: 123")
        #expect(event == nil)

        event = try await parser.parseLine("data:Test Data")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "custom")
        #expect(event?.id == "123")
        #expect(String(data: event!.data, encoding: .utf8) == "Test Data")
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

        event = try await parser.parseLine("data:actual data")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(String(data: event!.data, encoding: .utf8) == "actual data")
    }

    @Test("Retry Field")
    func testRetryField() async throws {
        let parser = SSEParser()

        // Valid retry value
        var event = try await parser.parseLine("retry: 5000")
        #expect(event == nil)

        event = try await parser.parseLine("data:test")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.retry == 5000)
        #expect(String(data: event!.data, encoding: .utf8) == "test")

        // Invalid retry value should be ignored
        event = try await parser.parseLine("retry: invalid")
        #expect(event == nil)

        event = try await parser.parseLine("data:test2")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.retry == nil)  // Previous retry value should not persist
        #expect(String(data: event!.data, encoding: .utf8) == "test2")
    }

    @Test("Empty Data Fields")
    func testEmptyDataFields() async throws {
        let parser = SSEParser()

        // Empty data fields should create newlines
        var event = try await parser.parseLine("data:")
        #expect(event == nil)

        event = try await parser.parseLine("data:Line")
        #expect(event == nil)

        event = try await parser.parseLine("data:")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(String(data: event!.data, encoding: .utf8) == "\nLine\n")
    }

    @Test("NULL Character in ID")
    func testNullCharacterInId() async throws {
        let parser = SSEParser()

        // ID with NULL should be ignored
        var event = try await parser.parseLine("id: 123\u{0000}456")
        #expect(event == nil)

        event = try await parser.parseLine("data:test")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.id == nil)  // ID should be ignored
        #expect(String(data: event!.data, encoding: .utf8) == "test")
    }

    @Test("Event Type Persistence")
    func testEventTypePersistence() async throws {
        let parser = SSEParser()

        // Set event type
        var event = try await parser.parseLine("event: custom")
        #expect(event == nil)

        event = try await parser.parseLine("data:first")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "custom")

        // Type should persist
        event = try await parser.parseLine("data:second")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "custom")

        // New type should override
        event = try await parser.parseLine("event: new")
        #expect(event == nil)

        event = try await parser.parseLine("data:third")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "new")
    }

    @Test("Event ID Persistence")
    func testEventIdPersistence() async throws {
        let parser = SSEParser()

        // Set event ID
        var event = try await parser.parseLine("id: 1")
        #expect(event == nil)

        event = try await parser.parseLine("data:first")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.id == "1")

        // ID should persist
        event = try await parser.parseLine("data:second")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.id == "1")

        // New ID should override
        event = try await parser.parseLine("id: 2")
        #expect(event == nil)

        event = try await parser.parseLine("data:third")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.id == "2")
    }

    @Test("UTF-8 Validation")
    func testUTF8Validation() async throws {
        let parser = SSEParser()

        // Valid UTF-8
        var event = try await parser.parseLine("data:Hello 世界")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(String(data: event!.data, encoding: .utf8) == "Hello 世界")

        // Invalid UTF-8 should be replaced with replacement character
        event = try await parser.parseLine("data:Hello \u{FFFD}")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(String(data: event!.data, encoding: .utf8)?.contains("\u{FFFD}") == true)
    }

    @Test("Flush Buffered Data")
    func testFlush() async throws {
        let parser = SSEParser()

        // Add some data without ending the event
        var event = try await parser.parseLine("event: custom")
        #expect(event == nil)

        event = try await parser.parseLine("data:buffered")
        #expect(event == nil)

        // Flush should return the buffered event
        let flushedEvent = await parser.flush()
        #expect(flushedEvent != nil)
        #expect(flushedEvent?.type == "custom")
        #expect(String(data: flushedEvent!.data, encoding: .utf8) == "buffered")

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

        event = try await parser.parseLine("id: 1")
        #expect(event == nil)

        event = try await parser.parseLine("retry: 5000")
        #expect(event == nil)

        event = try await parser.parseLine("data:test")
        #expect(event == nil)

        // Reset the parser
        await parser.reset()

        // Verify state is reset
        event = try await parser.parseLine("data:after reset")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "message")  // Back to default type
        #expect(event?.id == nil)          // ID should be cleared
        #expect(event?.retry == nil)       // Retry should be cleared
        #expect(String(data: event!.data, encoding: .utf8) == "after reset")
    }

    @Test("Whitespace Handling")
    func testWhitespaceHandling() async throws {
        let parser = SSEParser()

        // Per spec, only remove a single leading space after colon for data fields
        var event = try await parser.parseLine("event:  custom  ")
        #expect(event == nil)

        event = try await parser.parseLine("data: spaced data  ")
        #expect(event == nil)

        event = try await parser.parseLine("")
        #expect(event != nil)
        #expect(event?.type == "custom")  // Non-data fields trim all whitespace
        #expect(String(data: event!.data, encoding: .utf8) == "spaced data  ")  // Data fields preserve trailing whitespace
    }
}
