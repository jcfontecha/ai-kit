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

  func testDynamicTool_executeErrorTagsToolErrorDynamic() async throws {
    struct Boom: Error {}
    let model = MockLanguageModel(responses: [
      Self.response(finishReason: .toolCalls, content: [
        .toolCall(.init(toolCallID: "call-1", toolName: "weather", inputJSON: "{ \"city\": \"Madrid\" }")),
      ]),
      Self.response(finishReason: .stop, content: [.text("Done.", metadata: nil)]),
    ])

    let tools = dynamicRegistry(execute: { _, _ in throw Boom() })

    let result = try await generateText(
      model: model,
      prompt: "Weather?",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let content = try XCTUnwrap(result.steps.first?.content)
    let toolError = content.compactMap { part -> ToolError? in
      if case let .toolError(error) = part { return error }
      return nil
    }.first
    let error = try XCTUnwrap(toolError)
    XCTAssertEqual(error.toolName, "weather")
    XCTAssertEqual(error.dynamic, true)
  }

  func testDynamicTool_titlePropagatesToResult() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(finishReason: .toolCalls, content: [
        .toolCall(.init(toolCallID: "call-1", toolName: "weather", inputJSON: "{ \"city\": \"Madrid\" }")),
      ]),
      Self.response(finishReason: .stop, content: [.text("Done.", metadata: nil)]),
    ])

    var registry = ToolRegistry()
    registry.register(
      "weather",
      dynamicTool(
        title: "Weather Lookup",
        description: "Look up weather",
        inputSchema: .object(properties: ["city": .string()], required: ["city"], additionalProperties: false),
        execute: { _, _ in .final(.object(["ok": .bool(true)])) }
      )
    )

    let result = try await generateText(
      model: model,
      prompt: "Weather?",
      tools: registry,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let toolResult = try XCTUnwrap(result.steps.first?.toolResults.first)
    XCTAssertEqual(toolResult.dynamic, true)
    XCTAssertEqual(toolResult.title, "Weather Lookup")
  }

  func testDynamicTool_needsApprovalSurfacesApprovalRequest() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(finishReason: .toolCalls, content: [
        .toolCall(.init(toolCallID: "call-1", toolName: "weather", inputJSON: "{ \"city\": \"Madrid\" }")),
      ]),
    ])

    var registry = ToolRegistry()
    registry.register(
      "weather",
      dynamicTool(
        description: "Look up weather",
        inputSchema: .object(properties: ["city": .string()], required: ["city"], additionalProperties: false),
        needsApproval: { _, _ in true },
        execute: { _, _ in .final(.object(["ok": .bool(true)])) }
      )
    )

    let result = try await generateText(
      model: model,
      prompt: "Weather?",
      tools: registry,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let approval = result.steps.first?.content.compactMap { part -> ToolApprovalRequest? in
      if case let .toolApprovalRequest(request) = part { return request }
      return nil
    }.first
    let request = try XCTUnwrap(approval)
    XCTAssertEqual(request.toolCallID, "call-1")
    // No tool result emitted because execution is gated on approval.
    XCTAssertEqual(result.steps.first?.toolResults.count, 0)
  }

  func testDynamicTool_streamingPreliminaryThenFinal() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(finishReason: .toolCalls, content: [
        .toolCall(.init(toolCallID: "call-1", toolName: "weather", inputJSON: "{ \"city\": \"Madrid\" }")),
      ]),
      Self.response(finishReason: .stop, content: [.text("Done.", metadata: nil)]),
    ])

    let tools = dynamicRegistry(execute: { _, _ in
      .streaming(AsyncThrowingStream { continuation in
        continuation.yield(.preliminary(.object(["status": .string("loading")])))
        continuation.yield(.final(.object(["status": .string("done")])))
        continuation.finish()
      })
    })

    let result = try await generateText(
      model: model,
      prompt: "Weather?",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let toolResult = try XCTUnwrap(result.steps.first?.toolResults.last)
    XCTAssertEqual(toolResult.dynamic, true)
    XCTAssertEqual(toolResult.output, .object(["status": .string("done")]))
  }

  private final class SendableBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func set(_ newValue: Value) { lock.lock(); defer { lock.unlock() }; value = newValue }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
  }
}
