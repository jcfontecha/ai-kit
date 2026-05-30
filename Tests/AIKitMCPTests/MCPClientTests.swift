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
}
