import Foundation

/// Additional properties describing a Tool to clients.
///
/// NOTE: all properties in ToolAnnotations are **hints**.
/// They are not guaranteed to provide a faithful description of
/// tool behavior (including descriptive properties like `title`).
///
/// Clients should never make tool use decisions based on ToolAnnotations
/// received from untrusted servers.
public struct ToolAnnotations: Codable, Sendable, Hashable {

  // MARK: Lifecycle

  public init(
    title: String? = nil,
    readOnlyHint: Bool? = nil,
    destructiveHint: Bool? = nil,
    idempotentHint: Bool? = nil,
    openWorldHint: Bool? = nil)
  {
    self.title = title
    self.readOnlyHint = readOnlyHint
    self.destructiveHint = destructiveHint
    self.idempotentHint = idempotentHint
    self.openWorldHint = openWorldHint
  }

  // MARK: Public

  /// A human-readable title for the tool.
  public let title: String?

  /// If true, the tool does not modify its environment.
  /// Default: false
  public let readOnlyHint: Bool?

  /// If true, the tool may perform destructive updates to its environment.
  /// If false, the tool performs only additive updates.
  /// (This property is meaningful only when `readOnlyHint == false`)
  /// Default: true
  public let destructiveHint: Bool?

  /// If true, calling the tool repeatedly with the same arguments
  /// will have no additional effect on its environment.
  /// (This property is meaningful only when `readOnlyHint == false`)
  /// Default: false
  public let idempotentHint: Bool?

  /// If true, this tool may interact with an "open world" of external
  /// entities. If false, the tool's domain of interaction is closed.
  /// For example, the world of a web search tool is open, whereas that
  /// of a memory tool is not.
  /// Default: true
  public let openWorldHint: Bool?

}
