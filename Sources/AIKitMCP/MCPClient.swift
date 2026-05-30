import Foundation
import AIKitProviders

/// A tool advertised by an MCP server.
public struct MCPToolDefinition: Sendable, Equatable {
  public var name: String
  public var description: String?
  public var inputSchema: JSONSchema

  public init(name: String, description: String? = nil, inputSchema: JSONSchema) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
  }
}

/// A client for an MCP server over the Streamable HTTP transport.
///
/// Lifecycle: `connect()` performs the `initialize` handshake (capturing the `Mcp-Session-Id`), then
/// `tools()` / `listTools()` / `callTool(...)` may be used, and `close()` tears down the session.
/// The client is an `actor` so the request-id counter, session id, and connection state are
/// serialized.
public actor MCPClient {
  private let transport: HTTPTransport
  private let url: URL
  private let extraHeaders: [String: String]
  /// MCP protocol revision advertised by this client.
  private let protocolVersion = "2025-06-18"
  private let clientInfo: (name: String, version: String)

  private var sessionID: String?
  private var nextID = 1
  private var connected = false

  public init(
    url: URL,
    headers: [String: String] = [:],
    clientName: String = "AIKit",
    clientVersion: String = "0.1.0",
    transport: HTTPTransport = MCPURLSessionTransport()
  ) {
    self.url = url
    self.extraHeaders = headers
    self.clientInfo = (clientName, clientVersion)
    self.transport = transport
  }

  // MARK: - Lifecycle

  public func connect() async throws {
    let params: JSONValue = .object([
      "protocolVersion": .string(protocolVersion),
      "capabilities": .object([:]),
      "clientInfo": .object([
        "name": .string(clientInfo.name),
        "version": .string(clientInfo.version),
      ]),
    ])
    _ = try await rpc(method: "initialize", params: params)
    connected = true
    try await notify(method: "notifications/initialized", params: nil)
  }

  public func close() async throws {
    guard connected else { return }
    connected = false
    // Best-effort session teardown; servers without session support simply ignore it.
    var request = makeRequest(body: nil)
    request.httpMethod = "DELETE"
    _ = try? await transport.data(for: request)
    sessionID = nil
  }

  // MARK: - Tools

  public func listTools() async throws -> [MCPToolDefinition] {
    let result = try await rpc(method: "tools/list", params: .object([:]))
    guard case let .object(fields) = result, case let .array(tools)? = fields["tools"] else {
      return []
    }
    return tools.compactMap(Self.parseToolDefinition)
  }

  /// Calls a tool and returns the JSON-RPC `result` (e.g. `{ content: [...], isError, structuredContent }`).
  public func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
    let params: JSONValue = .object([
      "name": .string(name),
      "arguments": arguments,
    ])
    return try await rpc(method: "tools/call", params: params)
  }

  // MARK: - JSON-RPC plumbing

  private func nextRequestID() -> Int {
    defer { nextID += 1 }
    return nextID
  }

  private func makeRequest(body: Data?) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    for (key, value) in extraHeaders {
      request.setValue(value, forHTTPHeaderField: key)
    }
    if let sessionID {
      request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
    }
    if connected {
      request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
    }
    request.httpBody = body
    return request
  }

  /// Sends a request-bearing JSON-RPC message and returns its `result`, throwing on JSON-RPC errors.
  private func rpc(method: String, params: JSONValue?) async throws -> JSONValue {
    let id = nextRequestID()
    let message = JSONRPC.message(id: id, method: method, params: params)
    let request = makeRequest(body: try JSONRPC.encode(message))

    let (data, http) = try await transport.data(for: request)
    captureSession(from: http)
    guard (200..<300).contains(http.statusCode) else {
      throw MCPError.transport(statusCode: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
    }

    let messages = responseMessages(data: data, http: http)
    for object in messages {
      guard case let .object(fields) = object, JSONRPC.idMatches(fields["id"], id) else { continue }
      if case let .object(error)? = fields["error"] {
        let code: Int
        if case let .number(n)? = error["code"] { code = Int(n) } else { code = 0 }
        let detail: String
        if case let .string(m)? = error["message"] { detail = m } else { detail = "Unknown error" }
        throw MCPError.rpc(code: code, message: detail)
      }
      return fields["result"] ?? .null
    }
    throw MCPError.invalidResponse("No JSON-RPC response for id \(id) (method \(method)).")
  }

  /// Sends a notification (no `id`, no response expected).
  private func notify(method: String, params: JSONValue?) async throws {
    let message = JSONRPC.message(id: nil, method: method, params: params)
    let request = makeRequest(body: try JSONRPC.encode(message))
    let (_, http) = try await transport.data(for: request)
    captureSession(from: http)
  }

  private func responseMessages(data: Data, http: HTTPURLResponse) -> [JSONValue] {
    let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
    if contentType.contains("text/event-stream") {
      return JSONRPC.sseEvents(from: data).compactMap(JSONRPC.decode)
    }
    if data.isEmpty { return [] }
    return JSONRPC.decode(data).map { [$0] } ?? []
  }

  private func captureSession(from http: HTTPURLResponse) {
    if let id = http.value(forHTTPHeaderField: "Mcp-Session-Id"), id.isEmpty == false {
      sessionID = id
    }
  }

  private static func parseToolDefinition(_ value: JSONValue) -> MCPToolDefinition? {
    guard case let .object(fields) = value, case let .string(name)? = fields["name"] else {
      return nil
    }
    let description: String?
    if case let .string(text)? = fields["description"] { description = text } else { description = nil }
    let schema: JSONSchema
    if case let .object(schemaFields)? = fields["inputSchema"] {
      schema = JSONSchema(schemaFields)
    } else {
      schema = JSONSchema(["type": .string("object")])
    }
    return MCPToolDefinition(name: name, description: description, inputSchema: schema)
  }
}
