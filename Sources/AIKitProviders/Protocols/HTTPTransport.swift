import Foundation

public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
  func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse)
}

