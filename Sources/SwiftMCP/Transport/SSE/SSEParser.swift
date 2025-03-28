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
    /// The retry value in milliseconds (optional)
    public let retry: Int?

    public init(type: String = "message", id: String? = nil, data: Data, retry: Int? = nil) {
        self.type = type
        self.id = id
        self.data = data
        self.retry = retry
    }
}

/// Parser for Server-Sent Events (SSE)
public actor SSEParser {
    private var dataBuffer: [String]
    private var eventType: String
    private var eventID: String?
    private var retryTime: Int?

    public init() {
        self.dataBuffer = []
        self.eventType = "message"
        self.eventID = nil
        self.retryTime = nil
    }

    /// Parse a line of SSE input
    /// - Parameter line: The line to parse
    /// - Returns: An SSEEvent if a complete event was parsed, nil otherwise
    public func parseLine(_ line: String) throws -> SSEEvent? {
        // Trim only trailing newlines, preserve other whitespace
        let trimmedLine = line.trimmingCharacters(in: .newlines)

        // Empty line marks end of event
        if trimmedLine.isEmpty {
            return flushEvent()
        }

        // Skip comment lines
        if trimmedLine.hasPrefix(":") {
            return nil
        }

        // Parse field
        if trimmedLine.hasPrefix("event:") {
            // For non-data fields, trim all whitespace
            eventType = String(trimmedLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            logger.debug("Event type set to: \(self.eventType)")
        } else if trimmedLine.hasPrefix("data:") {
            // For data fields, only remove a single leading space if present
            let text = String(trimmedLine.dropFirst(5))
            dataBuffer.append(text.hasPrefix(" ") ? String(text.dropFirst()) : text)
            logger.debug("Added data line: \(text)")
        } else if trimmedLine.hasPrefix("id:") {
            // Per spec, if ID contains U+0000 NULL, ignore the ID
            let newID = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if !newID.contains("\u{0000}") {
                eventID = newID
                logger.debug("Event ID set to: \(newID)")
            }
        } else if trimmedLine.hasPrefix("retry:") {
            if let ms = Int(String(trimmedLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)) {
                retryTime = ms
                logger.debug("Retry value set to: \(ms)ms")
            }
        } else {
            logger.debug("Ignoring unknown SSE line: \(trimmedLine)")
        }

        return nil
    }

    /// Get any remaining buffered event
    /// - Returns: An SSEEvent if there is buffered data, nil otherwise
    public func flush() -> SSEEvent? {
        return flushEvent()
    }

    /// Reset the parser state
    public func reset() {
        dataBuffer.removeAll()
        eventType = "message"
        eventID = nil
        retryTime = nil
    }

    // MARK: - Private Methods

    private func flushEvent() -> SSEEvent? {
        guard !dataBuffer.isEmpty else { return nil }

        // Join data lines with newlines
        let data = dataBuffer.joined(separator: "\n")

        // Create event
        let event = SSEEvent(
            type: eventType,
            id: eventID,
            data: data.data(using: .utf8) ?? Data(),
            retry: retryTime
        )

        // Clear data buffer and retry time, but maintain event type and ID as per spec
        dataBuffer.removeAll()
        retryTime = nil

        return event
    }
}
