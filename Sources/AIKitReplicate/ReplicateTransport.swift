import Foundation
import AIKitProviders

struct ReplicateURLSessionTransport: HTTPTransport {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }
    return (data, http)
  }

  func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
    let (stream, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    let bytes = AsyncThrowingStream<UInt8, Error> { continuation in
      Task {
        do {
          for try await byte in stream {
            continuation.yield(byte)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
    return (bytes, http)
  }
}

