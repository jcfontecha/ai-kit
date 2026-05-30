import Foundation
import AIKitProviders
@testable import AIKitMCP

/// In-memory MCP server mock. Responds to JSON-RPC requests by method, echoing the request id, and
/// can answer as either `application/json` or `text/event-stream` to exercise both Streamable HTTP
/// response modes.
final class MCPTestServer: @unchecked Sendable {
  private let lock = NSLock()

  struct CallRecord {
    var method: String
    var params: JSONValue?
    var headers: [String: String]
  }

  /// method -> result JSONValue
  var results: [String: JSONValue]
  /// method -> (code, message) to return a JSON-RPC error instead of a result
  var errors: [String: (Int, String)]
  var useSSE: Bool
  var sessionID: String?

  private(set) var calls: [CallRecord] = []

  init(
    results: [String: JSONValue] = [:],
    errors: [String: (Int, String)] = [:],
    useSSE: Bool = false,
    sessionID: String? = nil
  ) {
    self.results = results
    self.errors = errors
    self.useSSE = useSSE
    self.sessionID = sessionID
  }

  func transport() -> HTTPTransport { TestTransport(server: self) }

  func recordedMethods() -> [String] {
    lock.lock(); defer { lock.unlock() }
    return calls.map(\.method)
  }

  func call(forMethod method: String) -> CallRecord? {
    lock.lock(); defer { lock.unlock() }
    return calls.last { $0.method == method }
  }

  private func record(_ record: CallRecord) {
    lock.lock(); defer { lock.unlock() }
    calls.append(record)
  }

  private final class TestTransport: @unchecked Sendable, HTTPTransport {
    let server: MCPTestServer
    init(server: MCPTestServer) { self.server = server }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      try respond(to: request)
    }

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
      let (data, response) = try respond(to: request)
      let stream = AsyncThrowingStream<UInt8, Error> { continuation in
        for byte in data { continuation.yield(byte) }
        continuation.finish()
      }
      return (stream, response)
    }

    private func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
      let bodyData = request.httpBody ?? Data()
      let body = JSONRPC.decode(bodyData)
      var method = ""
      var id: JSONValue?
      var params: JSONValue?
      if case let .object(fields)? = body {
        if case let .string(m)? = fields["method"] { method = m }
        id = fields["id"]
        params = fields["params"]
      }

      var headers: [String: String] = [:]
      for (key, value) in request.allHTTPHeaderFields ?? [:] { headers[key.lowercased()] = value }
      server.record(CallRecord(method: method, params: params, headers: headers))

      var responseHeaders: [String: String] = [:]
      if method == "initialize", let sessionID = server.sessionID {
        responseHeaders["Mcp-Session-Id"] = sessionID
      }

      // Notifications (no id) get a 202 with no body.
      guard let id else {
        let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: responseHeaders)!
        return (Data(), response)
      }

      let payload: JSONValue
      if let (code, message) = server.errors[method] {
        payload = .object([
          "jsonrpc": .string("2.0"),
          "id": id,
          "error": .object(["code": .number(Double(code)), "message": .string(message)]),
        ])
      } else {
        payload = .object([
          "jsonrpc": .string("2.0"),
          "id": id,
          "result": server.results[method] ?? .object([:]),
        ])
      }

      let data: Data
      if server.useSSE {
        responseHeaders["Content-Type"] = "text/event-stream"
        let json = String(data: try JSONRPC.encode(payload), encoding: .utf8) ?? "{}"
        data = "event: message\ndata: \(json)\n\n".data(using: .utf8) ?? Data()
      } else {
        responseHeaders["Content-Type"] = "application/json"
        data = try JSONRPC.encode(payload)
      }

      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: responseHeaders)!
      return (data, response)
    }
  }
}

let mcpTestURL = URL(string: "https://example.test/mcp")!
