import Foundation
import AIKitProviders

final class FalTestServer: @unchecked Sendable {
  private let lock = NSLock()
  enum ResponseType {
    case json(Data, headers: [String: String] = [:], status: Int = 200)
    case binary(Data, headers: [String: String] = [:], status: Int = 200)
  }

  struct CallRecord {
    var requestMethod: String
    var requestUrl: String
    var requestHeaders: [String: String]
    var requestBody: Data
    var requestBodyJSON: JSONValue?
  }

  var responses: [String: ResponseType] = [:]
  private(set) var calls: [CallRecord] = []

  func transport() -> HTTPTransport {
    TestTransport(server: self)
  }

  private final class TestTransport: @unchecked Sendable, HTTPTransport {
    let server: FalTestServer
    init(server: FalTestServer) { self.server = server }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      try await respond(for: request)
    }

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
      let (data, response) = try await respond(for: request)
      let stream = AsyncThrowingStream<UInt8, Error> { continuation in
        Task {
          for byte in data {
            continuation.yield(byte)
          }
          continuation.finish()
        }
      }
      return (stream, response)
    }

    private func respond(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      guard let url = request.url?.absoluteString else { throw URLError(.badURL) }
      let method = request.httpMethod ?? "GET"
      let key = "\(method) \(url)"
      guard let responseConfig = server.response(for: key) else {
        throw URLError(.badServerResponse)
      }

      var headers: [String: String] = [:]
      for (k, v) in (request.allHTTPHeaderFields ?? [:]) {
        headers[k.lowercased()] = v
      }
      let body = request.httpBody ?? Data()
      let bodyJSON = try? JSONDecoder().decode(JSONValue.self, from: body)

      server.recordCall(
        .init(
          requestMethod: method,
          requestUrl: url,
          requestHeaders: headers,
          requestBody: body,
          requestBodyJSON: bodyJSON
        )
      )

      let data: Data
      let status: Int
      let responseHeaders: [String: String]
      switch responseConfig {
      case .json(let payload, let headers, let code):
        data = payload
        responseHeaders = headers
        status = code
      case .binary(let payload, let headers, let code):
        data = payload
        responseHeaders = headers
        status = code
      }

      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: responseHeaders)!
      return (data, response)
    }
  }

  private func response(for key: String) -> ResponseType? {
    lock.lock()
    defer { lock.unlock() }
    return responses[key]
  }

  private func recordCall(_ record: CallRecord) {
    lock.lock()
    defer { lock.unlock() }
    calls.append(record)
  }
}
