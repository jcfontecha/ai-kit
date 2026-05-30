import XCTest
import AIKitProviders
@testable import AIKitMCP

final class MCPClientTests: XCTestCase {
  private func toolsListResult() -> JSONValue {
    .object([
      "tools": .array([
        .object([
          "name": .string("get_weather"),
          "description": .string("Get the weather for a city"),
          "inputSchema": .object([
            "type": .string("object"),
            "properties": .object(["city": .object(["type": .string("string")])]),
            "required": .array([.string("city")]),
          ]),
        ]),
        .object([
          "name": .string("get_time"),
          "inputSchema": .object(["type": .string("object")]),
        ]),
      ]),
    ])
  }

  private func server(useSSE: Bool = false, sessionID: String? = nil) -> MCPTestServer {
    MCPTestServer(
      results: [
        "initialize": .object(["protocolVersion": .string("2025-06-18")]),
        "tools/list": toolsListResult(),
        "tools/call": .object([
          "content": .array([.object(["type": .string("text"), "text": .string("Sunny, 21C")])]),
          "isError": .bool(false),
        ]),
      ],
      useSSE: useSSE,
      sessionID: sessionID
    )
  }

  func testConnectThenListTools() async throws {
    let server = server()
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    let tools = try await client.listTools()

    XCTAssertEqual(tools.count, 2)
    XCTAssertEqual(tools.first?.name, "get_weather")
    XCTAssertEqual(tools.first?.description, "Get the weather for a city")
    XCTAssertEqual(tools.first?.inputSchema.value["type"], .string("object"))
    XCTAssertEqual(tools.last?.name, "get_time")
    XCTAssertNil(tools.last?.description)

    // initialize, notifications/initialized, tools/list — in order.
    XCTAssertEqual(server.recordedMethods(), ["initialize", "notifications/initialized", "tools/list"])
  }

  func testListToolsOverSSE() async throws {
    let server = server(useSSE: true)
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    let tools = try await client.listTools()
    XCTAssertEqual(tools.map(\.name), ["get_weather", "get_time"])
  }

  func testCallToolReturnsResult() async throws {
    let server = server()
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    let output = try await client.callTool(name: "get_weather", arguments: .object(["city": .string("Madrid")]))

    XCTAssertEqual(
      output,
      .object([
        "content": .array([.object(["type": .string("text"), "text": .string("Sunny, 21C")])]),
        "isError": .bool(false),
      ])
    )
    // The arguments must be forwarded under params.arguments.
    let call = server.call(forMethod: "tools/call")
    guard case let .object(params)? = call?.params else { return XCTFail("missing params") }
    XCTAssertEqual(params["name"], .string("get_weather"))
    XCTAssertEqual(params["arguments"], .object(["city": .string("Madrid")]))
  }

  func testRPCErrorThrows() async throws {
    let server = server()
    server.errors["tools/call"] = (-32602, "Invalid params")
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()

    do {
      _ = try await client.callTool(name: "get_weather", arguments: .object([:]))
      XCTFail("expected throw")
    } catch let error as MCPError {
      XCTAssertEqual(error, .rpc(code: -32602, message: "Invalid params"))
    }
  }

  func testSessionIDForwardedAfterInitialize() async throws {
    let server = server(sessionID: "sess-123")
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    _ = try await client.listTools()

    let listCall = server.call(forMethod: "tools/list")
    XCTAssertEqual(listCall?.headers["mcp-session-id"], "sess-123")
    XCTAssertEqual(listCall?.headers["mcp-protocol-version"], "2025-06-18")
  }

  // MARK: - Schema conversion fidelity

  func testListToolsConvertsSchemasFaithfully() async throws {
    let nestedSchema: JSONValue = .object([
      "type": .string("object"),
      "properties": .object([
        "city": .object(["type": .string("string"), "description": .string("City name")]),
        "options": .object([
          "type": .string("object"),
          "properties": .object(["units": .object(["type": .string("string")])]),
          "required": .array([.string("units")]),
        ]),
      ]),
      "required": .array([.string("city")]),
    ])
    let server = MCPTestServer(results: [
      "initialize": .object(["protocolVersion": .string("2025-06-18")]),
      "tools/list": .object(["tools": .array([
        .object([
          "name": .string("get_weather"),
          "description": .string("Get the weather for a city"),
          "inputSchema": nestedSchema,
        ]),
        // No inputSchema -> defaults to an object schema.
        .object(["name": .string("ping")]),
        // No description -> nil description.
        .object([
          "name": .string("get_time"),
          "inputSchema": .object(["type": .string("object")]),
        ]),
      ])]),
    ])
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    let tools = try await client.listTools()

    let weather = try XCTUnwrap(tools.first { $0.name == "get_weather" })
    XCTAssertEqual(weather.description, "Get the weather for a city")
    // The full nested schema round-trips into inputSchema.value verbatim.
    XCTAssertEqual(JSONValue.object(weather.inputSchema.value), nestedSchema)

    let ping = try XCTUnwrap(tools.first { $0.name == "ping" })
    XCTAssertEqual(ping.inputSchema.value, ["type": .string("object")])
    XCTAssertNil(ping.description)

    let time = try XCTUnwrap(tools.first { $0.name == "get_time" })
    XCTAssertNil(time.description)
  }

  // MARK: - callTool result mapping

  func testCallToolReturnsStructuredResultAsIs() async throws {
    let fullResult: JSONValue = .object([
      "content": .array([.object(["type": .string("text"), "text": .string("Sunny, 21C")])]),
      "structuredContent": .object(["temperatureC": .number(21), "condition": .string("sunny")]),
      "isError": .bool(false),
    ])
    let server = MCPTestServer(results: [
      "initialize": .object(["protocolVersion": .string("2025-06-18")]),
      "tools/call": fullResult,
    ])
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    let output = try await client.callTool(name: "get_weather", arguments: .object(["city": .string("Madrid")]))

    // The full JSON-RPC result (content + structuredContent + isError) is returned untouched.
    XCTAssertEqual(output, fullResult)
    let call = server.call(forMethod: "tools/call")
    guard case let .object(params)? = call?.params else { return XCTFail("missing params") }
    XCTAssertEqual(params["name"], .string("get_weather"))
    XCTAssertEqual(params["arguments"], .object(["city": .string("Madrid")]))
  }

  // MARK: - JSON-RPC error exposure

  func testRPCErrorExposesCodeAndMessageForMethodNotFound() async throws {
    let server = server()
    server.errors["tools/call"] = (-32601, "Method not found")
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()

    do {
      _ = try await client.callTool(name: "missing", arguments: .object([:]))
      XCTFail("expected throw")
    } catch let error as MCPError {
      guard case let .rpc(code, message) = error else { return XCTFail("expected .rpc, got \(error)") }
      XCTAssertEqual(code, -32601)
      XCTAssertEqual(message, "Method not found")
    }
  }

  // MARK: - Transport errors

  func testTransportErrorSurfacesStatusAndBody() async throws {
    let server = server()
    server.statuses["tools/call"] = 500
    server.bodies["tools/call"] = Data("upstream exploded".utf8)
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()

    do {
      _ = try await client.callTool(name: "get_weather", arguments: .object([:]))
      XCTFail("expected throw")
    } catch let error as MCPError {
      XCTAssertEqual(error, .transport(statusCode: 500, body: "upstream exploded"))
    }
  }

  // MARK: - Invalid responses

  func testGarbageBodyThrowsInvalidResponse() async throws {
    let server = server()
    server.bodies["tools/call"] = Data("not json at all".utf8)
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()

    do {
      _ = try await client.callTool(name: "get_weather", arguments: .object([:]))
      XCTFail("expected throw")
    } catch let error as MCPError {
      guard case .invalidResponse = error else { return XCTFail("expected .invalidResponse, got \(error)") }
    }
  }

  func testEmptyBodyThrowsInvalidResponse() async throws {
    let server = server()
    server.bodies["tools/call"] = Data()
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()

    do {
      _ = try await client.callTool(name: "get_weather", arguments: .object([:]))
      XCTFail("expected throw")
    } catch let error as MCPError {
      guard case .invalidResponse = error else { return XCTFail("expected .invalidResponse, got \(error)") }
    }
  }

  func testResponseWithMismatchedIDThrowsInvalidResponse() async throws {
    let server = server()
    // A well-formed JSON-RPC response whose id never matches the request's id.
    server.bodies["tools/call"] = Data(#"{"jsonrpc":"2.0","id":999,"result":{"ok":true}}"#.utf8)
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()

    do {
      _ = try await client.callTool(name: "get_weather", arguments: .object([:]))
      XCTFail("expected throw")
    } catch let error as MCPError {
      guard case .invalidResponse = error else { return XCTFail("expected .invalidResponse, got \(error)") }
    }
  }

  // MARK: - SSE response mode

  func testCallToolOverSSEReturnsResult() async throws {
    let server = server(useSSE: true)
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    let output = try await client.callTool(name: "get_weather", arguments: .object(["city": .string("Madrid")]))

    XCTAssertEqual(
      output,
      .object([
        "content": .array([.object(["type": .string("text"), "text": .string("Sunny, 21C")])]),
        "isError": .bool(false),
      ])
    )
  }

  // MARK: - Notifications

  func testConnectSendsInitializedNotificationWithoutError() async throws {
    let server = server()
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    // connect() must tolerate the 202/no-body response to the notification.
    try await client.connect()

    // initialize (request) then notifications/initialized (notification, no id), in order.
    XCTAssertEqual(server.recordedMethods(), ["initialize", "notifications/initialized"])
    let notification = server.call(forMethod: "notifications/initialized")
    XCTAssertNotNil(notification)
    // A notification carries no id in its params/body wrapper; record it as a POST.
    XCTAssertEqual(notification?.httpMethod, "POST")
  }

  // MARK: - Custom headers

  func testCustomHeadersSentOnEveryRequest() async throws {
    let server = server()
    let client = MCPClient(
      url: mcpTestURL,
      headers: ["Authorization": "Bearer tok", "X-Tenant": "acme"],
      transport: server.transport()
    )
    try await client.connect()
    _ = try await client.listTools()

    for record in server.allCalls() {
      XCTAssertEqual(record.headers["authorization"], "Bearer tok", "missing on \(record.method)")
      XCTAssertEqual(record.headers["x-tenant"], "acme", "missing on \(record.method)")
    }
  }

  // MARK: - Session + protocol version

  func testNoSessionHeaderWhenServerReturnsNone() async throws {
    // Server returns no Mcp-Session-Id on initialize.
    let server = server(sessionID: nil)
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    _ = try await client.listTools()

    let listCall = server.call(forMethod: "tools/list")
    XCTAssertNil(listCall?.headers["mcp-session-id"])
    // The protocol version header is still sent once connected.
    XCTAssertEqual(listCall?.headers["mcp-protocol-version"], "2025-06-18")
  }

  // MARK: - close()

  func testCloseSendsDeleteAndClearsSession() async throws {
    let server = server(sessionID: "sess-123")
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    _ = try await client.listTools()
    try await client.close()

    let delete = server.call(forHTTPMethod: "DELETE")
    XCTAssertNotNil(delete, "close() should issue a DELETE")
    // The DELETE still carries the session id it is tearing down.
    XCTAssertEqual(delete?.headers["mcp-session-id"], "sess-123")

    // A second close() is a no-op (no further DELETE / requests recorded).
    let countBefore = server.allCalls().count
    try await client.close()
    XCTAssertEqual(server.allCalls().count, countBefore)
  }
}
