import Foundation
import AIKitProviders

struct OpenRouterURLSessionTransport: HTTPTransport, Sendable {
  var session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw OpenRouterInvalidResponseError(message: "Missing HTTPURLResponse.")
    }
    return (data, http)
  }

  func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw OpenRouterInvalidResponseError(message: "Missing HTTPURLResponse.")
    }

    let stream = AsyncThrowingStream<UInt8, Error> { continuation in
      Task {
        do {
          for try await byte in bytes {
            continuation.yield(byte)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }

    return (stream, http)
  }
}
