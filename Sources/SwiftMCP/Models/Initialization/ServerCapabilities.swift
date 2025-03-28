import Foundation

// MARK: - ServerCapabilities

public struct ServerCapabilities: Codable, Sendable {

  // MARK: Lifecycle

  public init(
    experimental: [String: [String: AnyCodable]]? = nil,
    logging: [String: AnyCodable]? = nil,
    prompts: PromptsCapability? = nil,
    resources: ResourcesCapability? = nil,
    tools: ToolsCapability? = nil)
  {
    self.experimental = experimental
    self.logging = logging
    self.prompts = prompts
    self.resources = resources
    self.tools = tools
  }

  // MARK: Public

  public struct PromptsCapability: Codable, Sendable, Equatable {
    public let listChanged: Bool?

    public init(listChanged: Bool? = nil) {
      self.listChanged = listChanged
    }
  }

  public struct ResourcesCapability: Codable, Sendable, Equatable {
    public let listChanged: Bool?
    public let subscribe: Bool?

    public init(listChanged: Bool? = nil, subscribe: Bool? = nil) {
      self.listChanged = listChanged
      self.subscribe = subscribe
    }
  }

  public struct ToolsCapability: Codable, Sendable, Equatable {
    public let listChanged: Bool?

    public init(listChanged: Bool? = nil) {
      self.listChanged = listChanged
    }
  }

  public var experimental: [String: [String: AnyCodable]]?
  public var logging: [String: AnyCodable]?
  public var prompts: PromptsCapability?
  public var resources: ResourcesCapability?
  public var tools: ToolsCapability?
}

// MARK: CustomStringConvertible

extension ServerCapabilities: CustomStringConvertible {
  public var description: String {
    var desc = "ServerCapabilities("
    if let prompts {
      desc += "prompts: \(prompts), "
    }
    if let resources {
      desc += "resources: \(resources), "
    }
    if let tools {
      desc += "tools: \(tools), "
    }
    desc += ")"
    return desc
  }
}

// MARK: Equatable

extension ServerCapabilities: Equatable {
  public static func ==(lhs: ServerCapabilities, rhs: ServerCapabilities) -> Bool {
    (lhs.prompts == rhs.prompts) && (lhs.resources == rhs.resources)
      && (lhs.tools == rhs.tools) && (lhs.experimental == rhs.experimental)
      && (lhs.logging == rhs.logging)
  }
}

extension ServerCapabilities {
  public struct Features: OptionSet {
    public let rawValue: Int

    public static let tools = Features(rawValue: 1 << 0)
    public static let resources = Features(rawValue: 1 << 1)
    public static let resourceListChanged = Features(rawValue: 1 << 2)
    public static let resourceSubscribe = Features(rawValue: 1 << 3)
    public static let prompts = Features(rawValue: 1 << 4)
    public static let promptListChanged = Features(rawValue: 1 << 5)
    public static let logging = Features(rawValue: 1 << 6)

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }
  }

  public var supportedFeatures: Features {
    var features = Features()
    if tools != nil { features.insert(.tools) }
    if let resources {
      features.insert(.resources)

      if resources.listChanged != nil {
        features.insert(.resourceListChanged)
      }

      if resources.subscribe != nil {
        features.insert(.resourceSubscribe)
      }
    }
    if let prompts {
      features.insert(.prompts)

      if prompts.listChanged != nil {
        features.insert(.promptListChanged)
      }
    }
    return features
  }

  public func supports(_ feature: Features) -> Bool {
    supportedFeatures.contains(feature)
  }
}
