import Foundation

extension AsyncSequence where Element == UInt8 {
  var allLines: AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      Task {
        var buffer: [UInt8] = []
        var iterator = self.makeAsyncIterator()
        do {
          while let byte = try await iterator.next() {
            if byte == UInt8(ascii: "\n") {
              if buffer.isEmpty {
                continuation.yield("")
              } else {
                if let line = String(data: Data(buffer), encoding: .utf8) {
                  continuation.yield(line)
                } else {
                  throw TransportError.invalidMessage("Could not decode SSE line as UTF-8.")
                }
                buffer.removeAll()
              }
            } else {
              buffer.append(byte)
            }
          }
          if !buffer.isEmpty, let line = String(data: Data(buffer), encoding: .utf8) {
            continuation.yield(line)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }
}
