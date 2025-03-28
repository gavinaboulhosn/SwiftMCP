import Foundation
import OSLog

private let logger = Logger(subsystem: "SwiftMCP", category: "SSEParser")

/// Represents an SSE event
public struct SSEEvent {
    /// The event type (defaults to "message")
    public let type: String
    /// The event ID (optional)
    public let id: String?
    /// The event data
    public let data: Data

    public init(type: String = "message", id: String? = nil, data: Data) {
        self.type = type
        self.id = id
        self.data = data
    }
}

/// Parser for Server-Sent Events (SSE)
public actor SSEParser {
    private var dataBuffer = Data()
    private var eventType = "message"
    private var eventID: String?

    public init() {}

    /// Parse a line of SSE input
    /// - Parameter line: The line to parse
    /// - Returns: An SSEEvent if a complete event was parsed, nil otherwise
    public func parseLine(_ line: String) throws -> SSEEvent? {
        // Trim whitespace and newlines
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.debug("Parsing SSE line: \(trimmedLine)")

        // Empty line marks end of event
        if trimmedLine.isEmpty {
            if !dataBuffer.isEmpty {
                let event = SSEEvent(type: eventType, id: eventID, data: dataBuffer)
                dataBuffer.removeAll()
                eventType = "message"  // Reset to default
                eventID = nil
                return event
            }
            return nil
        }

        // Skip comment lines
        if trimmedLine.hasPrefix(":") {
            return nil
        }

        // Parse field
        if trimmedLine.hasPrefix("event:") {
            eventType = String(trimmedLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            logger.debug("Event type set to: \(self.eventType)")
        } else if trimmedLine.hasPrefix("data:") {
            let text = String(trimmedLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if let chunk = (text + "\n").data(using: .utf8) {
                dataBuffer.append(chunk)
                logger.debug(
                    "Data buffer now contains: \(String(data: self.dataBuffer, encoding: .utf8) ?? "invalid utf8")"
                )
            }
        } else if trimmedLine.hasPrefix("id:") {
            eventID = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if trimmedLine.hasPrefix("retry:") {
            // Retry field is handled by the transport layer
            if let ms = Int(String(trimmedLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)) {
                logger.debug("Retry value received: \(ms)ms")
            }
        } else {
            logger.debug("Ignoring unknown SSE line: \(trimmedLine)")
        }

        return nil
    }

    /// Get any remaining buffered event
    /// - Returns: An SSEEvent if there is buffered data, nil otherwise
    public func flush() -> SSEEvent? {
        guard !dataBuffer.isEmpty else { return nil }
        let event = SSEEvent(type: eventType, id: eventID, data: dataBuffer)
        dataBuffer.removeAll()
        eventType = "message"
        eventID = nil
        return event
    }

    /// Reset the parser state
    public func reset() {
        dataBuffer.removeAll()
        eventType = "message"
        eventID = nil
    }
}
