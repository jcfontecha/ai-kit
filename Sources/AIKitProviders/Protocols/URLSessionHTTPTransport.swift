import Foundation

/// Default `HTTPTransport` implementation backed by `URLSession.shared`.
///
/// This is a client-side convenience for iOS/macOS apps consuming endpoints.
public struct URLSessionHTTPTransport: HTTPTransport {
  public init() {}

  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return (data, http)
  }

  public func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    let stream = AsyncThrowingStream(UInt8.self) { continuation in
      Task {
        do {
          for try await b in bytes { continuation.yield(b) }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
    return (stream, http)
  }
}

