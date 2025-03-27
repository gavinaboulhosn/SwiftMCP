import Foundation

public struct ClientCapabilities: Codable, Sendable {

  // MARK: Lifecycle

  public init(
    experimental: [String: [String: AnyCodable]]? = nil,
    roots: RootsCapability? = nil,
    sampling: [String: AnyCodable]? = nil)
  {
    self.experimental = experimental
    self.roots = roots
    self.sampling = sampling
  }

  // MARK: Public

  public struct RootsCapability: Codable, Sendable, Equatable {
    public let listChanged: Bool?

    public init(listChanged: Bool? = nil) {
      self.listChanged = listChanged
    }
  }

  public var experimental: [String: [String: AnyCodable]]?
  public var roots: RootsCapability?
  public var sampling: [String: AnyCodable]?
}

// MARK: Equatable

extension ClientCapabilities: Equatable {
  public static func ==(lhs: ClientCapabilities, rhs: ClientCapabilities) -> Bool {
    (lhs.roots == rhs.roots) && (lhs.experimental == rhs.experimental)
      && (lhs.sampling == rhs.sampling)
  }
}

// MARK: CustomStringConvertible

extension ClientCapabilities: CustomStringConvertible {
  public var description: String {
    var desc = "ClientCapabilities("
    if let roots {
      desc += "\nroots: \(roots),"
    }
    if let sampling {
      desc += "\nsampling: \(sampling),"
    }

    return desc + ")"
  }
}

extension ClientCapabilities {
  public struct Features: OptionSet {
    public let rawValue: Int

    public static let roots = Features(rawValue: 1 << 0)
    public static let sampling = Features(rawValue: 1 << 1)
    public static let experimental = Features(rawValue: 1 << 2)

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }
  }

  public var supportedFeatures: Features {
    var features = Features()
    if roots != nil { features.insert(.roots) }
    if sampling != nil { features.insert(.sampling) }
    if experimental != nil { features.insert(.experimental) }
    return features
  }

  public func supports(_ feature: Features) -> Bool {
    supportedFeatures.contains(feature)
  }
}
