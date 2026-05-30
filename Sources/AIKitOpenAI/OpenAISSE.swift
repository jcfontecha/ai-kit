import Foundation

func parseSSELines(_ stream: AsyncThrowingStream<UInt8, Error>) -> AsyncThrowingStream<String, Error> {
  AsyncThrowingStream<String, Error> { continuation in
    Task {
      var buffer = Data()
      do {
        for try await byte in stream {
          buffer.append(byte)
          while let range = buffer.range(of: Data([0x0A, 0x0A])) {
            let chunkData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            if let payload = parseSSEChunk(chunkData) {
              continuation.yield(payload)
            }
          }
        }

        if buffer.isEmpty == false {
          _ = parseSSEChunk(buffer).map { continuation.yield($0) }
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }
}

private func parseSSEChunk(_ data: Data) -> String? {
  guard let string = String(data: data, encoding: .utf8) else { return nil }
  let lines = string.split(separator: "\n")
  var dataLines: [String] = []
  for line in lines {
    if line.hasPrefix("data:") {
      let payload = line.dropFirst(5)
      let trimmed = payload.first == " " ? payload.dropFirst() : Substring(payload)
      dataLines.append(String(trimmed))
    }
  }
  if dataLines.isEmpty {
    return nil
  }
  return dataLines.joined(separator: "\n")
}
