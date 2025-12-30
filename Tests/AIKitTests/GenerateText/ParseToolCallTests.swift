import XCTest
@testable @_spi(Advanced) import AIKit
import AIKitProviders

final class ParseToolCallTests: XCTestCase {
  private struct TestInput: Codable, Sendable, Equatable {
    let param1: String
    let param2: Int
  }

  private struct EmptyInput: Codable, Sendable, Equatable {}

  private struct DummyOutput: Codable, Sendable, Equatable {}

  private func makeRegistry() -> ToolRegistry {
    var registry = ToolRegistry()
    registry.register(
      ToolID<TestInput, DummyOutput>("testTool"),
      ToolSpec(
        title: "Test Tool",
        inputSchema: .manual(
          jsonSchema: .object(
            properties: [
              "param1": .string(),
              "param2": .integer(),
            ],
            required: ["param1", "param2"],
            additionalProperties: false
          ),
          name: "TestInput"
        )
      )
    )
    return registry
  }

  func testParseToolCall_validToolCall() async {
    let registry = makeRegistry()
    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "testTool",
          inputJSON: "{\"param1\":\"test\",\"param2\":42}"
        ),
        tools: registry,
        repairToolCall: nil,
        messages: [],
        system: nil
      )
    )

    XCTAssertEqual(result.toolCallID, "123")
    XCTAssertEqual(result.toolName, "testTool")
    XCTAssertEqual(result.input, .object(["param1": .string("test"), "param2": .number(42)]))
    XCTAssertEqual(result.invalid, false)
    XCTAssertNil(result.error)
  }

  func testParseToolCall_providerExecutedDynamicToolCall() async {
    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "testTool",
          inputJSON: "{\"param1\":\"test\",\"param2\":42}",
          providerExecuted: true,
          dynamic: true,
          providerMetadata: ["testProvider": .object(["signature": .string("sig")])]
        ),
        tools: .init(),
        repairToolCall: nil,
        messages: [],
        system: nil
      )
    )

    XCTAssertEqual(result.toolCallID, "123")
    XCTAssertEqual(result.toolName, "testTool")
    XCTAssertEqual(result.input, .object(["param1": .string("test"), "param2": .number(42)]))
    XCTAssertEqual(result.providerExecuted, true)
    XCTAssertEqual(result.dynamic, true)
    XCTAssertEqual(
      result.providerMetadata,
      ["testProvider": .object(["signature": .string("sig")])]
    )
    XCTAssertFalse(result.invalid)
  }

  func testParseToolCall_providerMetadataPassthrough() async {
    let registry = makeRegistry()
    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "testTool",
          inputJSON: "{\"param1\":\"test\",\"param2\":42}",
          providerMetadata: ["testProvider": .object(["signature": .string("sig")])]
        ),
        tools: registry,
        repairToolCall: nil,
        messages: [],
        system: nil
      )
    )

    XCTAssertEqual(
      result.providerMetadata,
      ["testProvider": .object(["signature": .string("sig")])]
    )
  }

  func testParseToolCall_emptyInputStringForEmptySchema() async {
    var registry = ToolRegistry()
    registry.register(
      ToolID<EmptyInput, DummyOutput>("emptyTool"),
      ToolSpec(
        inputSchema: .manual(
          jsonSchema: .object(properties: [:], required: [], additionalProperties: false),
          name: "Empty"
        )
      )
    )

    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "emptyTool",
          inputJSON: ""
        ),
        tools: registry,
        repairToolCall: nil,
        messages: [],
        system: nil
      )
    )

    XCTAssertEqual(result.input, .object([:]))
    XCTAssertFalse(result.invalid)
  }

  func testParseToolCall_emptyObjectInputForEmptySchema() async {
    var registry = ToolRegistry()
    registry.register(
      ToolID<EmptyInput, DummyOutput>("emptyTool"),
      ToolSpec(
        inputSchema: .manual(
          jsonSchema: .object(properties: [:], required: [], additionalProperties: false),
          name: "Empty"
        )
      )
    )

    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "emptyTool",
          inputJSON: "{}"
        ),
        tools: registry,
        repairToolCall: nil,
        messages: [],
        system: nil
      )
    )

    XCTAssertEqual(result.input, .object([:]))
    XCTAssertFalse(result.invalid)
  }

  func testParseToolCall_noToolsAvailable() async {
    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "testTool",
          inputJSON: "{}"
        ),
        tools: nil,
        repairToolCall: nil,
        messages: [],
        system: nil
      )
    )

    XCTAssertTrue(result.invalid)
    XCTAssertEqual(result.dynamic, true)
    XCTAssertEqual(result.input, .object([:]))
    XCTAssertEqual(
      result.error?.message,
      "Model tried to call unavailable tool 'testTool'. No tools are available."
    )
  }

  func testParseToolCall_toolNotFound() async {
    let registry = makeRegistry()
    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "nonExistentTool",
          inputJSON: "{}"
        ),
        tools: registry,
        repairToolCall: nil,
        messages: [],
        system: nil
      )
    )

    XCTAssertTrue(result.invalid)
    XCTAssertEqual(result.dynamic, true)
    XCTAssertEqual(result.input, .object([:]))
    XCTAssertEqual(
      result.error?.message,
      "Model tried to call unavailable tool 'nonExistentTool'. Available tools: testTool."
    )
  }

  func testParseToolCall_invalidInput() async {
    let registry = makeRegistry()
    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "testTool",
          inputJSON: "{\"param1\":\"test\"}"
        ),
        tools: registry,
        repairToolCall: nil,
        messages: [],
        system: nil
      )
    )

    XCTAssertTrue(result.invalid)
    XCTAssertEqual(result.input, .object(["param1": .string("test")]))
    XCTAssertTrue(
      result.error?.message.hasPrefix(
        "Invalid input for tool testTool: Type validation failed: Value: {\"param1\":\"test\"}. Error message:"
      ) ?? false
    )
  }

  func testParseToolCall_repairToolCall_success() async {
    let registry = makeRegistry()
    final actor Flag {
      var value = false
      func setTrue() { value = true }
    }
    let repairFlag = Flag()

    let repair: ToolCallRepairFunction = { context in
      await repairFlag.setTrue()
      XCTAssertEqual(context.toolCall.toolName, "testTool")
      return ToolCall(
        toolCallID: "123",
        toolName: "testTool",
        inputJSON: "{\"param1\":\"test\",\"param2\":42}"
      )
    }

    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "testTool",
          inputJSON: "invalid json"
        ),
        tools: registry,
        repairToolCall: repair,
        messages: [ModelMessage(role: .user, content: [.text("test message")])],
        system: .instructions("test system")
      )
    )

    let wasCalled = await repairFlag.value
    XCTAssertTrue(wasCalled)
    XCTAssertFalse(result.invalid)
    XCTAssertEqual(result.input, .object(["param1": .string("test"), "param2": .number(42)]))
  }

  func testParseToolCall_repairToolCall_returnsNil() async {
    let registry = makeRegistry()
    let repair: ToolCallRepairFunction = { _ in nil }

    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "testTool",
          inputJSON: "invalid json"
        ),
        tools: registry,
        repairToolCall: repair,
        messages: [],
        system: nil
      )
    )

    XCTAssertTrue(result.invalid)
    XCTAssertEqual(result.input, .string("invalid json"))
    XCTAssertTrue(
      result.error?.message.hasPrefix(
        "Invalid input for tool testTool: JSON parsing failed: Text: invalid json. Error message:"
      ) ?? false
    )
  }

  func testParseToolCall_repairToolCall_throws() async {
    let registry = makeRegistry()
    let repair: ToolCallRepairFunction = { _ in
      throw NSError(domain: "test", code: 1)
    }

    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "testTool",
          inputJSON: "invalid json"
        ),
        tools: registry,
        repairToolCall: repair,
        messages: [],
        system: nil
      )
    )

    XCTAssertTrue(result.invalid)
    XCTAssertEqual(result.error?.message, "Error repairing tool call: Error Domain=test Code=1 \"(null)\"")
  }

  func testParseToolCall_dynamicToolCallFlagPreserved() async {
    let registry = makeRegistry()
    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "testTool",
          inputJSON: "{\"param1\":\"test\",\"param2\":42}",
          dynamic: true
        ),
        tools: registry,
        repairToolCall: nil,
        messages: [],
        system: nil
      )
    )

    XCTAssertEqual(result.dynamic, true)
  }

  func testParseToolCall_titleIncludedForInvalid() async {
    let registry = makeRegistry()
    let result = await parseToolCall(
      .init(
        toolCall: .init(
          toolCallID: "123",
          toolName: "testTool",
          inputJSON: "invalid json"
        ),
        tools: registry,
        repairToolCall: nil,
        messages: [],
        system: nil
      )
    )

    XCTAssertEqual(result.title, "Test Tool")
    XCTAssertTrue(result.invalid)
  }
}
