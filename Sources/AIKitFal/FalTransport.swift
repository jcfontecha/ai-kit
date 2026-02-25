import Foundation
import AIKitProviders

final class FalURLSessionTransport: HTTPTransport {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }
    return (data, http)
  }

  func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
    let (data, response) = try await data(for: request)
    let stream = AsyncThrowingStream<UInt8, Error> { continuation in
      Task {
        for byte in data { continuation.yield(byte) }
        continuation.finish()
      }
    }
    return (stream, response)
  }
}

