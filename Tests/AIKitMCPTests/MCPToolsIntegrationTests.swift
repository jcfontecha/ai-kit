import XCTest
import AIKitProviders
import AIKitTestKit
@testable @_spi(Advanced) import AIKit
@testable import AIKitMCP

final class MCPToolsIntegrationTests: XCTestCase {
  private static func response(finishReason: FinishReason, content: [ModelContentPart]) -> ModelResponse {
    .init(
      content: content,
      finishReason: finishReason,
      rawFinishReason: finishReason.rawValue,
      usage: .init(),
      warnings: [],
      request: .init(),
      response: .init(),
      providerMetadata: nil
    )
  }

  func testMCPToolRunsThroughGenerateTextAndIsDynamic() async throws {
    let server = MCPTestServer(results: [
      "initialize": .object([:]),
      "tools/list": .object(["tools": .array([
        .object([
          "name": .string("get_weather"),
          "description": .string("Get weather"),
          "inputSchema": .object(["type": .string("object")]),
        ]),
      ])]),
      "tools/call": .object([
        "content": .array([.object(["type": .string("text"), "text": .string("Sunny")])]),
        "isError": .bool(false),
      ]),
    ])

    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    let tools = try await client.toolRegistry()

    let model = MockLanguageModel(responses: [
      Self.response(finishReason: .toolCalls, content: [
        .toolCall(.init(
          toolCallID: "call-1",
          toolName: "get_weather",
          inputJSON: "{ \"city\": \"Madrid\" }"
        )),
      ]),
      Self.response(finishReason: .stop, content: [.text("Done.", metadata: nil)]),
    ])

    let result = try await generateText(
      model: model,
      prompt: "Weather in Madrid?",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let toolResult = try XCTUnwrap(result.steps.first?.toolResults.first)
    XCTAssertEqual(toolResult.toolName, "get_weather")
    XCTAssertEqual(toolResult.dynamic, true)
    XCTAssertEqual(
      toolResult.output,
      .object([
        "content": .array([.object(["type": .string("text"), "text": .string("Sunny")])]),
        "isError": .bool(false),
      ])
    )
    // The model's tool input reached the MCP server as call arguments.
    let call = server.call(forMethod: "tools/call")
    guard case let .object(params)? = call?.params else { return XCTFail("missing params") }
    XCTAssertEqual(params["arguments"], .object(["city": .string("Madrid")]))
  }

  func testToolsBridgeProducesOneSpecPerServerTool() async throws {
    let weatherSchema: JSONValue = .object([
      "type": .string("object"),
      "properties": .object(["city": .object(["type": .string("string")])]),
      "required": .array([.string("city")]),
    ])
    let server = MCPTestServer(results: [
      "initialize": .object([:]),
      "tools/list": .object(["tools": .array([
        .object([
          "name": .string("get_weather"),
          "description": .string("Get weather"),
          "inputSchema": weatherSchema,
        ]),
        .object([
          "name": .string("get_time"),
          "inputSchema": .object(["type": .string("object")]),
        ]),
      ])]),
      "tools/call": .object(["content": .array([.object(["type": .string("text"), "text": .string("Sunny")])])]),
    ])
    let client = MCPClient(url: mcpTestURL, transport: server.transport())
    try await client.connect()
    let tools = try await client.tools()

    XCTAssertEqual(Set(tools.keys), ["get_weather", "get_time"])

    let weather = try XCTUnwrap(tools["get_weather"])
    XCTAssertEqual(weather.description, "Get weather")
    XCTAssertEqual(JSONValue.object(weather.inputSchema.value), weatherSchema)
    XCTAssertNotNil(weather.execute)

    let time = try XCTUnwrap(tools["get_time"])
    XCTAssertNil(time.description)
    XCTAssertEqual(time.inputSchema.value, ["type": .string("object")])

    // Executing a bridged spec calls back into the MCP server.
    let context = ToolContext(toolCallID: "call-x", messages: [])
    let execution = try await XCTUnwrap(weather.execute)(.object(["city": .string("Oslo")]), context)
    guard case let .final(output) = execution else { return XCTFail("expected final output") }
    XCTAssertEqual(output, .object(["content": .array([.object(["type": .string("text"), "text": .string("Sunny")])])]))
    let call = server.call(forMethod: "tools/call")
    guard case let .object(params)? = call?.params else { return XCTFail("missing params") }
    XCTAssertEqual(params["name"], .string("get_weather"))
    XCTAssertEqual(params["arguments"], .object(["city": .string("Oslo")]))
  }
}
