import Foundation

/// The type of content in a message or resource
public enum ContentType: String, Codable, Sendable {
  case text
  case image
  case audio
  case resource
}
