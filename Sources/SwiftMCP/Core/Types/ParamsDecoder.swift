import Foundation

/// Utility function to decode parameters from an AnyCodable dictionary
func decodeParams<T: Decodable>(
  _: T.Type,
  from dict: [String: AnyCodable]?)
  -> T?
{
  guard let dict else {
    // If T has no required fields, attempt to decode an empty dictionary
    let data = try? JSONEncoder().encode([String: AnyCodable]())
    return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }

  // Use JSONEncoder to encode the dictionary
  guard let data = try? JSONEncoder().encode(dict) else {
    NSLog("Failed to encode params using JSONEncoder.")
    return nil
  }

  // Decode the data into the desired type
  do {
    return try JSONDecoder().decode(T.self, from: data)
  } catch {
    NSLog("Decoding failed with error: \(error)")
    return nil
  }
}
