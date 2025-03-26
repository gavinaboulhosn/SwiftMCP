import Foundation

extension KeyedEncodingContainer {
  mutating func encodeAny(_ value: Encodable, forKey key: Key) throws {
    let wrapper = AnyEncodable(value)
    try encode(wrapper, forKey: key)
  }
}

/// A type-erased Encodable wrapper.
struct AnyEncodable: Encodable {
  private let encodeFunc: (Encoder) throws -> Void

  init(_ value: Encodable) {
    encodeFunc = { encoder in
      try value.encode(to: encoder)
    }
  }

  func encode(to encoder: Encoder) throws {
    try encodeFunc(encoder)
  }
}
