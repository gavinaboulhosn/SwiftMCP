import Foundation

/// Metadata for requests, such as progress tracking information
public struct RequestMeta: Codable, Sendable {
  var progressToken: ProgressToken?
}
