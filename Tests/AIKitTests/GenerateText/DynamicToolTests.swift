import XCTest
import AIKitProviders
import AIKitTestKit
@testable @_spi(Advanced) import AIKit

final class DynamicToolTests: XCTestCase {
  private static func response(
    finishReason: FinishReason,
    content: [ModelContentPart]
  ) -> ModelResponse {
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

  private func dynamicRegistry(
    execute: @escaping @Sendable (JSONValue, ToolContext) async throws -> ToolExecution<JSONValue>
  ) -> ToolRegistry {
    var registry = ToolRegistry()
    registry.register(
      "weather",
      dynamicTool(
        description: "Look up weather",
        inputSchema: .object(
          properties: ["city": .string()],
          required: ["city"],
          additionalProperties: false
        ),
        execute: execute
      )
    )
    return registry
  }

  func testDynamicTool_executesAndTagsResultDynamic() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(.init(
            toolCallID: "call-1",
            toolName: "weather",
            inputJSON: "{ \"city\": \"Madrid\" }"
          )),
        ]
      ),
      Self.response(finishReason: .stop, content: [.text("Done.", metadata: nil)]),
    ])

    let tools = dynamicRegistry(execute: { input, _ in
      guard case let .object(fields) = input, case let .string(city)? = fields["city"] else {
        return .final(.object(["error": .string("bad input")]))
      }
      return .final(.object(["temperature": .number(21), "city": .string(city)]))
    })

    let result = try await generateText(
      model: model,
      prompt: "Weather in Madrid?",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let toolResults = try XCTUnwrap(result.steps.first?.toolResults)
    XCTAssertEqual(toolResults.count, 1)
    let toolResult = try XCTUnwrap(toolResults.first)
    XCTAssertEqual(toolResult.toolName, "weather")
    XCTAssertEqual(toolResult.dynamic, true)
    XCTAssertEqual(toolResult.output, .object(["temperature": .number(21), "city": .string("Madrid")]))
  }

  func testDynamicTool_passthroughInputReachesExecute() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(.init(
            toolCallID: "call-1",
            toolName: "weather",
            inputJSON: "{ \"city\": \"Tokyo\", \"extra\": 5 }"
          )),
        ]
      ),
      Self.response(finishReason: .stop, content: [.text("ok", metadata: nil)]),
    ])

    let receivedInput = SendableBox<JSONValue?>(nil)
    let tools = dynamicRegistry(execute: { input, _ in
      receivedInput.set(input)
      return .final(.object(["ok": .bool(true)]))
    })

    _ = try await generateText(
      model: model,
      prompt: "Weather in Tokyo?",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    // Extra (non-schema) fields pass through untouched: dynamic tools do not validate input.
    XCTAssertEqual(
      receivedInput.get(),
      .object(["city": .string("Tokyo"), "extra": .number(5)])
    )
  }

  private final class SendableBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func set(_ newValue: Value) { lock.lock(); defer { lock.unlock() }; value = newValue }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
  }
}
