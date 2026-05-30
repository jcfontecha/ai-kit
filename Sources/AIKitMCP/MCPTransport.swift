import Foundation
import AIKitProviders

/// Default `URLSession`-backed transport for the MCP Streamable HTTP protocol.
public struct MCPURLSessionTransport: HTTPTransport, Sendable {
  var session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw MCPError.invalidResponse("Missing HTTPURLResponse.")
    }
    return (data, http)
  }

  public func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw MCPError.invalidResponse("Missing HTTPURLResponse.")
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
