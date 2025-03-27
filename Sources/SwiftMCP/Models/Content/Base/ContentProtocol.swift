import Foundation

/// Base protocol for all content types in MCP
public protocol MCPContent: Codable, Sendable, Hashable {
    /// The type of content
    var type: ContentType { get }

    /// Optional annotations for the client
    var annotations: Annotations? { get }
}

/// Base protocol for content that includes binary data
public protocol BinaryContent: MCPContent {
    /// The base64-encoded data
    var data: String { get }

    /// The MIME type of the content
    var mimeType: String { get }
}
