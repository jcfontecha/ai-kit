import XCTest
import AIKitProviders
import AIKitTestKit
@testable @_spi(Advanced) import AIKitCore

final class StreamTextTests: XCTestCase {
  private struct TestError: Error, Equatable {}
  private struct ToolInput: Codable, Sendable, Equatable {
    let value: String
  }

  private struct Person: Codable, Sendable, Equatable {
    let name: String
  }

  private struct Item: Codable, Sendable, Equatable {
    let value: String
  }

  private let usage = Usage(
    inputTokens: .init(total: 3, noCache: 3, cacheRead: nil, cacheWrite: nil),
    outputTokens: .init(total: 10, text: 10, reasoning: nil)
  )

  private func makeStream(_ parts: [ModelStreamPart]) -> AsyncThrowingStream<ModelStreamPart, Error> {
    AsyncThrowingStream(ModelStreamPart.self) { continuation in
      for part in parts {
        continuation.yield(part)
      }
      continuation.finish()
    }
  }

  private final class StreamQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [AsyncThrowingStream<ModelStreamPart, Error>]

    init(_ streams: [AsyncThrowingStream<ModelStreamPart, Error>]) {
      self.streams = streams
    }

    func next() -> AsyncThrowingStream<ModelStreamPart, Error> {
      lock.lock()
      defer { lock.unlock() }
      if streams.isEmpty {
        return AsyncThrowingStream(ModelStreamPart.self) { $0.finish() }
      }
      return streams.removeFirst()
    }
  }

  private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int = 0

    func increment() {
      lock.lock()
      defer { lock.unlock() }
      value += 1
    }

    func set(_ newValue: Int) {
      lock.lock()
      defer { lock.unlock() }
      value = newValue
    }

    func get() -> Int {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  private actor ChunkRecorder {
    private var chunks: [TextStreamPart] = []

    func append(_ chunk: TextStreamPart) {
      chunks.append(chunk)
    }

    func snapshot() -> [TextStreamPart] {
      chunks
    }
  }

  private final class MessageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func set(_ newValue: String) {
      lock.lock()
      defer { lock.unlock() }
      value = newValue
    }

    func get() -> String? {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ModelRequest?

    func set(_ newValue: ModelRequest) {
      lock.lock()
      defer { lock.unlock() }
      value = newValue
    }

    func get() -> ModelRequest? {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  private final class DownloadRequestsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [DownloadRequest] = []

    func set(_ newValue: [DownloadRequest]) {
      lock.lock()
      defer { lock.unlock() }
      value = newValue
    }

    func get() -> [DownloadRequest] {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  private func makeModel(stream: @escaping @Sendable (ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error>)
    -> MockLanguageModel {
    MockLanguageModel(
      generate: { _ in
        .init(content: [], finishReason: .stop, rawFinishReason: "stop")
      },
      stream: stream
    )
  }

  private func toolRegistry(
    needsApproval: ToolNeedsApproval<ToolInput>? = nil,
    execute: (@Sendable (ToolInput, ToolContext) async throws -> ToolExecution<String>)? = nil
  ) -> ToolRegistry {
    var registry = ToolRegistry()
    registry.register(
      ToolID<ToolInput, String>("testTool"),
      ToolSpec(
        title: "Test Tool",
        inputSchema: .manual(
          jsonSchema: .object(
            properties: ["value": .string()],
            required: ["value"],
            additionalProperties: false
          ),
          name: "ToolInput"
        ),
        needsApproval: needsApproval,
        execute: execute
      )
    )
    return registry
  }

  private func personSchema() -> ObjectSchema<Person> {
    .manual(
      jsonSchema: .object(
        properties: ["name": .string()],
        required: ["name"],
        additionalProperties: false
      ),
      name: "Person"
    )
  }

  private func itemSchema() -> ObjectSchema<Item> {
    .manual(
      jsonSchema: .object(
        properties: ["value": .string()],
        required: ["value"],
        additionalProperties: false
      ),
      name: "Item"
    )
  }

  func testTextStream_sendsTextDeltas() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textDelta(id: "1", text: ", ", providerMetadata: nil),
        .textDelta(id: "1", text: "world!", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.text()
    )

    let text = try await AsyncTestHelpers.collect(result.textStream)
    XCTAssertEqual(text, ["Hello", ", ", "world!"])
  }

  func testTextStream_filtersEmptyDeltas() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textDelta(id: "1", text: "", providerMetadata: nil),
        .textDelta(id: "1", text: ", ", providerMetadata: nil),
        .textDelta(id: "1", text: "", providerMetadata: nil),
        .textDelta(id: "1", text: "world!", providerMetadata: nil),
        .textDelta(id: "1", text: "", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.text()
    )

    let text = try await AsyncTestHelpers.collect(result.textStream)
    XCTAssertEqual(text, ["Hello", ", ", "world!"])
  }

  func testTextStream_excludesReasoning() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .reasoningStart(id: "r1", providerMetadata: nil),
        .reasoningDelta(id: "r1", text: "Think", providerMetadata: nil),
        .reasoningEnd(id: "r1", providerMetadata: nil),
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.text()
    )

    let text = try await AsyncTestHelpers.collect(result.textStream)
    XCTAssertEqual(text, ["Hello"])
  }

  func testFullStream_basicTextIncludesFinishStep() async throws {
    let responseMetadata = LanguageModelResponseMetadata(
      id: "response-id",
      modelID: "response-model-id",
      timestamp: Date(timeIntervalSince1970: 5)
    )

    let model = makeModel { _ in
      self.makeStream([
        .responseMetadata(responseMetadata),
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textDelta(id: "1", text: ", ", providerMetadata: nil),
        .textDelta(id: "1", text: "world!", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.text()
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertEqual(
      events,
      [
        .start,
        .startStep(request: .init(), warnings: []),
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textDelta(id: "1", text: ", ", providerMetadata: nil),
        .textDelta(id: "1", text: "world!", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finishStep(
          response: responseMetadata,
          usage: usage,
          finishReason: .stop,
          rawFinishReason: nil,
          providerMetadata: nil
        ),
        .finish(finishReason: .stop, rawFinishReason: nil, totalUsage: usage),
      ]
    )
  }

  func testFullStream_usesDefaultResponseMetadataWhenMissing() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.text()
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    guard let finishStep = events.first(where: {
      if case .finishStep = $0 { return true }
      return false
    }) else {
      XCTFail("Missing finish-step event")
      return
    }

    if case let .finishStep(response, _, _, _, _) = finishStep {
      XCTAssertEqual(response, LanguageModelResponseMetadata())
    } else {
      XCTFail("Expected finish-step event")
    }
  }

  func testStreamText_warningsFromFirstStep() async throws {
    let warning = CallWarning(message: "warning", code: "unsupported-parameter")

    let model = makeModel { _ in
      self.makeStream([
        .streamStart(warnings: [warning]),
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.text()
    )

    let warnings = try await result.warnings
    XCTAssertEqual(warnings ?? [], [warning])
  }

  func testStreamText_toolApprovalStopsAfterOneStep() async throws {
    let tools = toolRegistry(needsApproval: { _, _ in true })

    let model = makeModel { _ in
      self.makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"needs-approval\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text()
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains { part in
      guard case let .toolApprovalRequest(request) = part else { return false }
      return request.toolCallID == "call-1" && request.approvalID == "id-0"
    })

    let steps = try await result.steps
    XCTAssertEqual(steps.count, 1)
    XCTAssertEqual(steps.first?.finishReason, .toolCalls)
  }

  func testStreamText_approvalApprovedExecutesBeforeLoop() async throws {
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let assistantMessage = ModelMessage(
      role: .assistant,
      content: [
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value\" }",
            input: .object(["value": .string("value")])
          )
        ),
        .toolApprovalRequest(
          .init(approvalID: "approval-1", toolCallID: "call-1", toolCall: nil)
        ),
      ]
    )

    let toolMessage = ModelMessage(
      role: .tool,
      content: [
        .toolApprovalResponse(
          .init(approvalID: "approval-1", approved: true)
        ),
      ]
    )

    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Done.", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        messages: [assistantMessage, toolMessage],
        tools: tools,
        output: Output.text()
      )
    )

    let steps = try await result.steps
    let responseMessages = steps.first?.responseMessages ?? []
    XCTAssertTrue(responseMessages.contains { message in
      guard message.role == .tool else { return false }
      return message.content.contains { part in
        if case let .toolResult(result) = part {
          return result.toolCallID == "call-1"
        }
        return false
      }
    })
  }

  func testStreamText_providerApprovalRequestIncludesToolCall() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "serverTool",
            inputJSON: "{ \"value\": \"v\" }",
            providerExecuted: true,
            dynamic: true
          )
        ),
        .toolApprovalRequest(.init(approvalID: "approval-1", toolCallID: "call-1")),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text()
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains { part in
      guard case let .toolApprovalRequest(request) = part else { return false }
      return request.toolCallID == "call-1" && request.toolCall != nil
    })
  }

  func testStreamText_approvalWithPreliminaryResultsWaitsForFinal() async throws {
    let tools = toolRegistry(needsApproval: { _, _ in true }, execute: { input, _ in
      let stream = AsyncThrowingStream<ToolProgress<String>, Error> { continuation in
        continuation.yield(.preliminary("pre-\(input.value)"))
        continuation.yield(.final("final-\(input.value)"))
        continuation.finish()
      }
      return .streaming(stream)
    })

    let model = makeModel { _ in
      self.makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text()
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertFalse(events.contains { part in
      guard case let .toolResult(result) = part else { return false }
      return result.preliminary == true
    })
  }

  func testStreamText_providerApprovalApprovedSkipsLocalExecution() async throws {
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let assistantMessage = ModelMessage(
      role: .assistant,
      content: [
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "serverTool",
            inputJSON: "{ \"value\": \"value\" }",
            providerExecuted: true,
            dynamic: true
          )
        ),
        .toolApprovalRequest(
          .init(approvalID: "approval-1", toolCallID: "call-1", toolCall: nil)
        ),
      ]
    )

    let toolMessage = ModelMessage(
      role: .tool,
      content: [
        .toolApprovalResponse(
          .init(approvalID: "approval-1", approved: true)
        ),
      ]
    )

    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Done.", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        messages: [assistantMessage, toolMessage],
        tools: tools,
        output: Output.text()
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertFalse(events.contains { part in
      guard case let .toolResult(result) = part else { return false }
      return result.toolCallID == "call-1"
    })
  }

  func testStreamText_providerApprovalDeniedDoesNotEmitToolOutputDenied() async throws {
    let tools = toolRegistry()

    let assistantMessage = ModelMessage(
      role: .assistant,
      content: [
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "serverTool",
            inputJSON: "{ \"value\": \"value\" }",
            providerExecuted: true,
            dynamic: true
          )
        ),
        .toolApprovalRequest(
          .init(approvalID: "approval-1", toolCallID: "call-1", toolCall: nil)
        ),
      ]
    )

    let toolMessage = ModelMessage(
      role: .tool,
      content: [
        .toolApprovalResponse(
          .init(approvalID: "approval-1", approved: false, reason: "no")
        ),
      ]
    )

    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Done.", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        messages: [assistantMessage, toolMessage],
        tools: tools,
        output: Output.text()
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertFalse(events.contains { part in
      if case .toolOutputDenied = part { return true }
      return false
    })
  }

  func testStreamText_dynamicToolCallIsNotExecutedLocally() async throws {
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let model = makeModel { _ in
      self.makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "unknownTool",
            inputJSON: "{ \"value\": \"value\" }",
            dynamic: true
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text()
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains { part in
      guard case let .toolCall(call) = part else { return false }
      return call.toolName == "unknownTool" && call.dynamic == true
    })
    XCTAssertFalse(events.contains { part in
      if case .toolResult = part { return true }
      return false
    })
  }

  func testStreamText_providerExecutedDeferredToolResult() async throws {
    let tools = toolRegistry()

    let queue = StreamQueue([
      makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "serverTool",
            inputJSON: "{ \"value\": \"value\" }",
            providerExecuted: true,
            dynamic: true
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ]),
      makeStream([
        .toolResult(
          .init(
            toolCallID: "call-1",
            toolName: "serverTool",
            inputJSON: "{ \"value\": \"value\" }",
            input: .object(["value": .string("value")]),
            output: .string("ok"),
            preliminary: false,
            providerExecuted: true,
            dynamic: true
          )
        ),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ]),
    ])

    let model = makeModel { _ in
      queue.next()
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text()
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains { part in
      guard case let .toolResult(result) = part else { return false }
      return result.toolCallID == "call-1" && result.providerExecuted == true
    })
  }

  func testStreamText_programmaticToolCallingMultiStep() async throws {
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let queue = StreamQueue([
      makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ]),
      makeStream([
        .toolCall(
          .init(
            toolCallID: "call-2",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value-2\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ]),
      makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Done.", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ]),
    ])

    let model = makeModel { _ in
      queue.next()
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        stopWhen: [Stop.stepCountIs(3)],
        output: Output.text()
      )
    )

    let steps = try await result.steps
    XCTAssertEqual(steps.count, 3)
    XCTAssertEqual(steps.first?.toolCalls.count, 1)
    XCTAssertEqual(steps.dropFirst().first?.toolCalls.count, 1)
    let text = try await result.text
    XCTAssertEqual(text, "Done.")
  }

  func testStreamText_stopWhenMultipleConditionsStopsWhenAnyTrue() async throws {
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let queue = StreamQueue([
      makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ]),
      makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Done.", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ]),
      makeStream([
        .textStart(id: "2", providerMetadata: nil),
        .textDelta(id: "2", text: "Extra", providerMetadata: nil),
        .textEnd(id: "2", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ]),
    ])

    let model = makeModel { _ in
      queue.next()
    }

    let evalCount = CounterBox()
    let stopWhen: [StopCondition] = [
      Stop.stepCountIs(2),
      { steps in
        evalCount.increment()
        return steps.count >= 2
      },
    ]

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        stopWhen: stopWhen,
        output: Output.text()
      )
    )

    let steps = try await result.steps
    XCTAssertEqual(steps.count, 2)
    XCTAssertTrue(evalCount.get() > 0)
    let text = try await result.text
    XCTAssertEqual(text, "Done.")
  }

  func testStreamText_prepareStepOverridesModelAndSystem() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "First", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let otherModel = makeModel { request in
      XCTAssertEqual(request.messages.first?.role, .system)
      return self.makeStream([
        .textStart(id: "2", providerMetadata: nil),
        .textDelta(id: "2", text: "Second", providerMetadata: nil),
        .textEnd(id: "2", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        prepareStep: { context in
          if context.stepNumber == 1 {
            return .init(
              model: otherModel,
              system: .text("override")
            )
          }
          return nil
        },
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text()
      )
    )

    let text = try await result.text
    XCTAssertEqual(text, "Second")
  }

  func testStreamText_prepareStepOverridesMessages() async throws {
    let model = makeModel { request in
      XCTAssertEqual(request.messages.first?.role, .user)
      return self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "First", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let otherModel = makeModel { request in
      XCTAssertEqual(request.messages.first?.role, .user)
      return self.makeStream([
        .textStart(id: "2", providerMetadata: nil),
        .textDelta(id: "2", text: "Second", providerMetadata: nil),
        .textEnd(id: "2", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        prepareStep: { context in
          if context.stepNumber == 1 {
            return .init(
              model: otherModel,
              messages: [.user("override")]
            )
          }
          return nil
        },
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text()
      )
    )

    let text = try await result.text
    XCTAssertEqual(text, "Second")
  }

  func testStreamText_prepareStepUsesModelSupportedURLsForDownload() async throws {
    let downloadBox = DownloadRequestsBox()
    let requestBox = RequestBox()

    let modelWithSupport = MockLanguageModel(
      supportedURLs: [
        "image/*": [URLPattern("^https?:\\/\\/.*$")]
      ],
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { _ in
        self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "ignored", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let modelWithoutSupport = MockLanguageModel(
      supportedURLs: [:],
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { request in
        requestBox.set(request)
        return self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "response from without-image-url-support", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let download: DownloadFunction = { requests in
      downloadBox.set(requests)
      return requests.map { request in
        request.isURLSupportedByModel
          ? nil
          : DownloadedAsset(data: Data([1, 2, 3, 4]), mediaType: "image/png")
      }
    }

    let result = streamText(
      .init(
        model: modelWithSupport,
        messages: [
          .init(
            role: .user,
            content: [
              .text("Describe this image"),
              .image(
                .init(
                  data: .url(URL(string: "https://example.com/test.jpg")!)
                )
              ),
            ]
          ),
        ],
        prepareStep: { _ in .init(model: modelWithoutSupport) },
        download: download,
        output: Output.text()
      )
    )

    let text = try await result.text
    XCTAssertEqual(text, "response from without-image-url-support")

    let downloadRequests = downloadBox.get()
    XCTAssertEqual(downloadRequests.count, 1)
    XCTAssertEqual(downloadRequests.first?.url.absoluteString, "https://example.com/test.jpg")
    XCTAssertEqual(downloadRequests.first?.isURLSupportedByModel, false)

    guard let request = requestBox.get() else {
      XCTFail("Expected model request")
      return
    }
    guard let userMessage = request.messages.first else {
      XCTFail("Expected user message")
      return
    }
    XCTAssertEqual(userMessage.role, .user)
    XCTAssertEqual(userMessage.content.count, 2)
    guard case let .image(image) = userMessage.content[1] else {
      XCTFail("Expected image part")
      return
    }
    guard case let .data(data) = image.data else {
      XCTFail("Expected downloaded image data")
      return
    }
    XCTAssertEqual(data, Data([1, 2, 3, 4]))
    XCTAssertEqual(image.mediaType, "image/png")
  }

  func testStreamText_imageDataURLConvertsToBase64AndMediaType() async throws {
    let requestBox = RequestBox()

    let model = MockLanguageModel(
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { request in
        requestBox.set(request)
        return self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "ok", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let dataURL = URL(string: "data:image/png;base64,QUJDRA==")!

    let result = streamText(
      .init(
        model: model,
        messages: [
          .init(
            role: .user,
            content: [
              .text("Describe this image"),
              .image(.init(data: .url(dataURL))),
            ]
          ),
        ],
        output: Output.text()
      )
    )

    _ = try await result.text

    guard let request = requestBox.get(),
          let userMessage = request.messages.first
    else {
      XCTFail("Expected request with user message")
      return
    }

    guard case let .image(image) = userMessage.content.last else {
      XCTFail("Expected image part")
      return
    }

    guard case let .base64(base64) = image.data else {
      XCTFail("Expected base64 data for data URL")
      return
    }

    XCTAssertEqual(base64, "QUJDRA==")
    XCTAssertEqual(image.mediaType, "image/png")
  }

  func testStreamText_filePartRequiresMediaType() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "ok", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        messages: [
          .init(
            role: .user,
            content: [
              .file(.init(data: .base64("AAAA"))),
            ]
          ),
        ],
        output: Output.text()
      )
    )

    do {
      _ = try await result.text
      XCTFail("Expected missing media type error")
    } catch {
      XCTAssertEqual(
        String(describing: error),
        "invalidConfiguration(\"Media type is missing for file part.\")"
      )
    }
  }

  func testStreamText_fileURLSupportedPassesThroughWithoutDownload() async throws {
    let requestBox = RequestBox()
    let downloadBox = DownloadRequestsBox()

    let model = MockLanguageModel(
      supportedURLs: [
        "application/pdf": [URLPattern("^https?:\\/\\/.*$")]
      ],
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { request in
        requestBox.set(request)
        return self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "ok", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let download: DownloadFunction = { requests in
      downloadBox.set(requests)
      return requests.map { request in
        request.isURLSupportedByModel
          ? nil
          : DownloadedAsset(data: Data([9, 9, 9]), mediaType: "application/pdf")
      }
    }

    let result = streamText(
      .init(
        model: model,
        messages: [
          .init(
            role: .user,
            content: [
              .file(
                .init(
                  data: .url(URL(string: "https://example.com/test.pdf")!),
                  filename: "test.pdf",
                  mediaType: "application/pdf"
                )
              ),
            ]
          ),
        ],
        download: download,
        output: Output.text()
      )
    )

    _ = try await result.text

    let downloadRequests = downloadBox.get()
    XCTAssertEqual(downloadRequests.count, 1)
    XCTAssertEqual(downloadRequests.first?.isURLSupportedByModel, true)

    guard let request = requestBox.get(),
          let userMessage = request.messages.first
    else {
      XCTFail("Expected request with user message")
      return
    }

    guard case let .file(file) = userMessage.content.first else {
      XCTFail("Expected file part")
      return
    }

    guard case let .url(url) = file.data else {
      XCTFail("Expected file URL to pass through")
      return
    }

    XCTAssertEqual(url.absoluteString, "https://example.com/test.pdf")
    XCTAssertEqual(file.mediaType, "application/pdf")
  }

  func testStreamText_fileURLUnsupportedDownloadsData() async throws {
    let requestBox = RequestBox()
    let downloadBox = DownloadRequestsBox()

    let model = MockLanguageModel(
      supportedURLs: [:],
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { request in
        requestBox.set(request)
        return self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "ok", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let download: DownloadFunction = { requests in
      downloadBox.set(requests)
      return requests.map { _ in
        DownloadedAsset(data: Data([9, 9, 9]), mediaType: "application/pdf")
      }
    }

    let result = streamText(
      .init(
        model: model,
        messages: [
          .init(
            role: .user,
            content: [
              .file(
                .init(
                  data: .url(URL(string: "https://example.com/test.pdf")!),
                  filename: "test.pdf",
                  mediaType: "application/pdf"
                )
              ),
            ]
          ),
        ],
        download: download,
        output: Output.text()
      )
    )

    _ = try await result.text

    let downloadRequests = downloadBox.get()
    XCTAssertEqual(downloadRequests.count, 1)
    XCTAssertEqual(downloadRequests.first?.isURLSupportedByModel, false)

    guard let request = requestBox.get(),
          let userMessage = request.messages.first
    else {
      XCTFail("Expected request with user message")
      return
    }

    guard case let .file(file) = userMessage.content.first else {
      XCTFail("Expected file part")
      return
    }

    guard case let .data(data) = file.data else {
      XCTFail("Expected downloaded file data")
      return
    }

    XCTAssertEqual(data, Data([9, 9, 9]))
    XCTAssertEqual(file.mediaType, "application/pdf")
  }

  func testStreamText_fileURLMissingMediaTypeThrowsEvenWithDownload() async throws {
    let downloadBox = DownloadRequestsBox()

    let model = MockLanguageModel(
      supportedURLs: [:],
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { _ in
        self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "ok", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let download: DownloadFunction = { requests in
      downloadBox.set(requests)
      return requests.map { _ in
        DownloadedAsset(data: Data([9, 9, 9]), mediaType: "application/pdf")
      }
    }

    let result = streamText(
      .init(
        model: model,
        messages: [
          .init(
            role: .user,
            content: [
              .file(
                .init(
                  data: .url(URL(string: "https://example.com/test.pdf")!)
                )
              ),
            ]
          ),
        ],
        download: download,
        output: Output.text()
      )
    )

    do {
      _ = try await result.text
      XCTFail("Expected missing media type error")
    } catch {
      XCTAssertEqual(
        String(describing: error),
        "invalidConfiguration(\"Media type is missing for file part.\")"
      )
    }
  }

  func testStreamText_imageMediaTypeDetectionOverridesProvided() async throws {
    let requestBox = RequestBox()
    let pngBase64 = "iVBORw0KGgo="

    let model = MockLanguageModel(
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { request in
        requestBox.set(request)
        return self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "ok", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let result = streamText(
      .init(
        model: model,
        messages: [
          .init(
            role: .user,
            content: [
              .image(
                .init(
                  data: .base64(pngBase64),
                  mediaType: "image/jpeg"
                )
              ),
            ]
          ),
        ],
        output: Output.text()
      )
    )

    _ = try await result.text

    guard let request = requestBox.get(),
          let userMessage = request.messages.first
    else {
      XCTFail("Expected request with user message")
      return
    }

    guard case let .image(image) = userMessage.content.first else {
      XCTFail("Expected image part")
      return
    }

    XCTAssertEqual(image.mediaType, "image/png")
  }

  func testStreamText_supportedURLsWildcardMatchesAnyMediaType() async throws {
    let downloadBox = DownloadRequestsBox()

    let model = MockLanguageModel(
      supportedURLs: [
        "*/*": [URLPattern("^https?:\\/\\/.*$")]
      ],
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { _ in
        self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "ok", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let download: DownloadFunction = { requests in
      downloadBox.set(requests)
      return requests.map { _ in nil }
    }

    let result = streamText(
      .init(
        model: model,
        messages: [
          .init(
            role: .user,
            content: [
              .file(
                .init(
                  data: .url(URL(string: "https://example.com/test.pdf")!),
                  mediaType: "application/pdf"
                )
              ),
            ]
          ),
        ],
        download: download,
        output: Output.text()
      )
    )

    _ = try await result.text

    let downloadRequests = downloadBox.get()
    XCTAssertEqual(downloadRequests.count, 1)
    XCTAssertEqual(downloadRequests.first?.isURLSupportedByModel, true)
  }

  func testStreamText_filtersEmptyTextPartsInUserMixedContent() async throws {
    let requestBox = RequestBox()

    let model = MockLanguageModel(
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { request in
        requestBox.set(request)
        return self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "ok", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let result = streamText(
      .init(
        model: model,
        messages: [
          .init(
            role: .user,
            content: [
              .text(""),
              .image(.init(data: .base64("AAAA"), mediaType: "image/png")),
              .text("Describe"),
            ]
          ),
        ],
        output: Output.text()
      )
    )

    _ = try await result.text

    guard let request = requestBox.get(),
          let userMessage = request.messages.first
    else {
      XCTFail("Expected request with user message")
      return
    }

    XCTAssertEqual(userMessage.content.count, 2)
    guard case .image = userMessage.content[0] else {
      XCTFail("Expected image first after filtering")
      return
    }
    guard case let .text(text) = userMessage.content[1] else {
      XCTFail("Expected trailing text part")
      return
    }
    XCTAssertEqual(text, "Describe")
  }

  func testStreamText_filtersEmptyTextPartsInAssistantContent() async throws {
    let requestBox = RequestBox()

    let model = MockLanguageModel(
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { request in
        requestBox.set(request)
        return self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "ok", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let result = streamText(
      .init(
        model: model,
        messages: [
          .init(
            role: .assistant,
            content: [
              .text(""),
              .text("Kept"),
            ]
          ),
          .init(
            role: .user,
            content: [.text("Hi")]
          ),
        ],
        output: Output.text()
      )
    )

    _ = try await result.text

    guard let request = requestBox.get() else {
      XCTFail("Expected request")
      return
    }

    guard let assistantMessage = request.messages.first(where: { $0.role == .assistant }) else {
      XCTFail("Expected assistant message")
      return
    }

    XCTAssertEqual(assistantMessage.content.count, 1)
    guard case let .text(text) = assistantMessage.content[0] else {
      XCTFail("Expected assistant text part")
      return
    }
    XCTAssertEqual(text, "Kept")
  }

  func testStreamText_imageWildcardMatchesButImagePngDoesNotForJpeg() async throws {
    let downloadBox = DownloadRequestsBox()

    let model = MockLanguageModel(
      supportedURLs: [
        "image/*": [URLPattern("^https?:\\/\\/example\\.com\\/.*$")],
        "image/png": [URLPattern("^https?:\\/\\/png-only\\.com\\/.*$")]
      ],
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { _ in
        self.makeStream([
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "ok", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
        ])
      }
    )

    let download: DownloadFunction = { requests in
      downloadBox.set(requests)
      return requests.map { _ in nil }
    }

    let result = streamText(
      .init(
        model: model,
        messages: [
          .init(
            role: .user,
            content: [
              .image(
                .init(
                  data: .url(URL(string: "https://example.com/test.jpg")!),
                  mediaType: "image/jpeg"
                )
              ),
            ]
          ),
        ],
        download: download,
        output: Output.text()
      )
    )

    _ = try await result.text

    let downloadRequests = downloadBox.get()
    XCTAssertEqual(downloadRequests.count, 1)
    XCTAssertEqual(downloadRequests.first?.isURLSupportedByModel, true)
  }

  func testStreamText_resultSurfaceAreaReflectsLastStepAndTotals() async throws {
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let usage1 = Usage(
      inputTokens: .init(total: 2, noCache: 2, cacheRead: nil, cacheWrite: nil),
      outputTokens: .init(total: 3, text: 3, reasoning: nil)
    )
    let usage2 = Usage(
      inputTokens: .init(total: 4, noCache: 4, cacheRead: nil, cacheWrite: nil),
      outputTokens: .init(total: 5, text: 5, reasoning: nil)
    )

    let warnings = [CallWarning(message: "first-step-warning")]
    let req1 = LanguageModelRequestMetadata(body: .object(["step": .number(1)]))
    let req2 = LanguageModelRequestMetadata(body: .object(["step": .number(2)]))
    let resp1 = LanguageModelResponseMetadata(id: "resp-1", modelID: "m1", timestamp: Date(timeIntervalSince1970: 10))
    let resp2 = LanguageModelResponseMetadata(id: "resp-2", modelID: "m2", timestamp: Date(timeIntervalSince1970: 20))

    let queue = StreamQueue([
      makeStream([
        .startStep(request: req1, warnings: warnings),
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value\" }"
          )
        ),
        .responseMetadata(resp1),
        .finish(finishReason: .toolCalls, usage: usage1, providerMetadata: nil),
      ]),
      makeStream([
        .startStep(request: req2, warnings: []),
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Done.", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .responseMetadata(resp2),
        .finish(finishReason: .stop, usage: usage2, providerMetadata: nil),
      ]),
    ])

    let model = makeModel { _ in queue.next() }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text()
      )
    )

    let steps = try await result.steps
    XCTAssertEqual(steps.count, 2)
    XCTAssertEqual(steps.first?.warnings, warnings)
    XCTAssertEqual(steps.last?.request, req2)
    XCTAssertEqual(steps.last?.response, resp2)

    let totalUsage = try await result.totalUsage
    let totalInput = (usage1.inputTokens?.total ?? 0) + (usage2.inputTokens?.total ?? 0)
    let totalNoCache = (usage1.inputTokens?.noCache ?? 0) + (usage2.inputTokens?.noCache ?? 0)
    let totalOutput = (usage1.outputTokens?.total ?? 0) + (usage2.outputTokens?.total ?? 0)
    let totalText = (usage1.outputTokens?.text ?? 0) + (usage2.outputTokens?.text ?? 0)
    let expectedUsage = Usage(
      inputTokens: .init(
        total: totalInput,
        noCache: totalNoCache,
        cacheRead: nil,
        cacheWrite: nil
      ),
      outputTokens: .init(
        total: totalOutput,
        text: totalText,
        reasoning: nil
      )
    )
    XCTAssertEqual(totalUsage, expectedUsage)

    let usage = try await result.usage
    let finishReason = try await result.finishReason
    XCTAssertEqual(usage, usage2)
    XCTAssertEqual(finishReason, .stop)
    let rawFinishReason = try await result.rawFinishReason
    XCTAssertNil(rawFinishReason)

    let toolCalls = try await result.toolCalls
    let toolResults = try await result.toolResults
    XCTAssertEqual(toolCalls.count, 0)
    XCTAssertEqual(toolResults.count, 0)
    XCTAssertEqual(steps.first?.toolCalls.count, 1)
    XCTAssertEqual(steps.first?.toolResults.count, 1)

    let responseMessages = steps.last?.responseMessages ?? []
    XCTAssertTrue(responseMessages.contains(where: { $0.role == .tool }))
  }

  func testStreamText_responseMessagesSurface() async throws {
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let queue = StreamQueue([
      makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ]),
      makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Done.", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ]),
    ])

    let model = makeModel { _ in queue.next() }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text()
      )
    )

    let responseMessages = try await result.responseMessages
    XCTAssertTrue(responseMessages.contains(where: { $0.role == .tool }))
  }

  func testStreamText_streamErrorRejectsResult() async throws {
    let model = MockLanguageModel(
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          continuation.finish(throwing: NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "test error"
          ]))
        }
      }
    )

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text()
      )
    )

    do {
      _ = try await result.text
      XCTFail("Expected stream error")
    } catch let error as AIKitError {
      XCTAssertEqual(
        error,
        .invalidConfiguration("No output generated. Check the stream for errors.")
      )
    }
  }

  func testStreamText_swallowErrorToPreventCrash() async throws {
    let model = MockLanguageModel(
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          continuation.finish(throwing: NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "test error"
          ]))
        }
      }
    )

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text()
      )
    )

    let text = try await AsyncTestHelpers.collect(result.textStream)
    XCTAssertEqual(text, [])
  }

  func testStreamText_fullStreamEmitsErrorPartOnStreamThrow() async throws {
    let model = MockLanguageModel(
      generate: { _ in .init(content: [], finishReason: .stop, rawFinishReason: "stop") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          continuation.finish(throwing: NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "test error"
          ]))
        }
      }
    )

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text()
      )
    )

    let parts = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(parts.contains { part in
      if case let .error(message) = part {
        return message == "test error"
      }
      return false
    })
  }

  func testStreamText_onFinishCalledAfterErrorChunk() async throws {
    let onFinishBox = MessageBox()
    let onErrorBox = MessageBox()

    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .error(.init(message: "chunk error")),
        .finish(finishReason: .error, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text(),
        onError: { message in
          onErrorBox.set(message)
        },
        onFinish: { event in
          onFinishBox.set(event.finishReason.rawValue)
        }
      )
    )

    try await result.consumeStream()

    XCTAssertEqual(onErrorBox.get(), "chunk error")
    XCTAssertEqual(onFinishBox.get(), FinishReason.error.rawValue)
  }

  func testStreamText_abortInSecondStepEmitsAbortAndStops() async throws {
    let token = CancellationToken()
    let queue = StreamQueue([
      makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "First", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ]),
      makeStream([
        .textStart(id: "2", providerMetadata: nil),
        .textDelta(id: "2", text: "Second", providerMetadata: nil),
        .textEnd(id: "2", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ]),
    ])

    let model = makeModel { _ in queue.next() }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        cancellationToken: token,
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text()
      )
    )

    var stepStarts = 0
    var sawAbort = false
    for try await part in result.fullStream {
      if case .startStep = part {
        stepStarts += 1
        if stepStarts == 2 {
          await token.cancel()
        }
      }
      if case .abort = part {
        sawAbort = true
      }
    }

    XCTAssertTrue(sawAbort)
    let finishReason = try await result.finishReason
    XCTAssertEqual(finishReason, FinishReason.error)
  }

  func testStreamText_fullStreamMixedContentOrder() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .startStep(request: .init(), warnings: []),
        .textStart(id: "t1", providerMetadata: nil),
        .textDelta(id: "t1", text: "Hi ", providerMetadata: nil),
        .reasoningStart(id: "r1", providerMetadata: nil),
        .reasoningDelta(id: "r1", text: "think", providerMetadata: nil),
        .toolInputStart(id: "call-1", toolName: "testTool", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
        .toolInputDelta(id: "call-1", delta: "{", providerMetadata: nil),
        .toolInputEnd(id: "call-1", providerMetadata: nil),
        .reasoningEnd(id: "r1", providerMetadata: nil),
        .textDelta(id: "t1", text: "there", providerMetadata: nil),
        .textEnd(id: "t1", providerMetadata: nil),
        .finishStep(
          response: .init(),
          usage: self.usage,
          finishReason: .stop,
          rawFinishReason: "stop",
          providerMetadata: nil
        ),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text()
      )
    )

    let parts = try await AsyncTestHelpers.collect(result.fullStream)
    let expected: [TextStreamPart] = [
      .start,
      .startStep(request: .init(), warnings: []),
      .textStart(id: "t1", providerMetadata: nil),
      .textDelta(id: "t1", text: "Hi ", providerMetadata: nil),
      .reasoningStart(id: "r1", providerMetadata: nil),
      .reasoningDelta(id: "r1", text: "think", providerMetadata: nil),
      .toolInputStart(id: "call-1", toolName: "testTool", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
      .toolInputDelta(id: "call-1", delta: "{", providerMetadata: nil),
      .toolInputEnd(id: "call-1", providerMetadata: nil),
      .reasoningEnd(id: "r1", providerMetadata: nil),
      .textDelta(id: "t1", text: "there", providerMetadata: nil),
      .textEnd(id: "t1", providerMetadata: nil),
      .finishStep(
        response: .init(),
        usage: self.usage,
        finishReason: .stop,
        rawFinishReason: "stop",
        providerMetadata: nil
      ),
      .finish(finishReason: .stop, rawFinishReason: "stop", totalUsage: self.usage),
    ]
    XCTAssertEqual(parts, expected)
  }

  func testStreamText_stepInputsIncludeAssistantAndToolMessages() async throws {
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let queue = StreamQueue([
      makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ]),
      makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Done.", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ]),
    ])

    let model = makeModel { _ in
      queue.next()
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text()
      )
    )

    _ = try await result.text

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(requests.first?.messages.count, 1)
    XCTAssertEqual(requests.first?.messages.first?.role, .user)

    let secondMessages = requests.dropFirst().first?.messages ?? []
    XCTAssertEqual(secondMessages.count, 3)
    XCTAssertEqual(secondMessages.first?.role, .user)
    XCTAssertEqual(secondMessages.dropFirst().first?.role, .assistant)
    XCTAssertEqual(secondMessages.dropFirst(2).first?.role, .tool)

    let assistantParts = secondMessages.dropFirst().first?.content ?? []
    XCTAssertTrue(assistantParts.contains { part in
      if case .toolCall = part { return true }
      return false
    })

    let toolParts = secondMessages.dropFirst(2).first?.content ?? []
    XCTAssertTrue(toolParts.contains { part in
      if case .toolResult = part { return true }
      return false
    })
  }

  func testFullStream_reasoningDeltasAreForwarded() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .reasoningStart(id: "r1", providerMetadata: nil),
        .reasoningDelta(id: "r1", text: "Think", providerMetadata: nil),
        .reasoningDelta(id: "r1", text: " more", providerMetadata: nil),
        .reasoningEnd(id: "r1", providerMetadata: nil),
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.text()
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains(.reasoningStart(id: "r1", providerMetadata: nil)))
    XCTAssertTrue(events.contains(.reasoningDelta(id: "r1", text: "Think", providerMetadata: nil)))
    XCTAssertTrue(events.contains(.reasoningDelta(id: "r1", text: " more", providerMetadata: nil)))
    XCTAssertTrue(events.contains(.reasoningEnd(id: "r1", providerMetadata: nil)))
    let reasoningText = try await result.reasoningText
    XCTAssertEqual(reasoningText, "Think more")
  }

  func testFullStream_toolCallEmitsToolResult() async throws {
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let model = makeModel { _ in
      self.makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      tools: tools,
      output: Output.text()
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains { part in
      guard case let .toolCall(call) = part else { return false }
      return call.toolCallID == "call-1"
    })
    XCTAssertTrue(events.contains { part in
      guard case let .toolResult(result) = part else { return false }
      return result.toolCallID == "call-1"
        && result.output == .string("result for value")
    })
  }

  func testFullStream_toolApprovalRequest() async throws {
    let tools = toolRegistry(needsApproval: { _, _ in true })

    let model = makeModel { _ in
      self.makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"needs-approval\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      tools: tools,
      output: Output.text()
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains { part in
      guard case let .toolApprovalRequest(request) = part else { return false }
      return request.approvalID == "id-0" && request.toolCallID == "call-1"
    })
  }

  func testFullStream_rawPartsHonorsIncludeRawParts() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .raw(.object(["key": .string("value")])),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      includeRawParts: true,
      output: Output.text()
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains(.raw(.object(["key": .string("value")]))))
  }

  func testPartialOutputStream_json() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "{", providerMetadata: nil),
        .textDelta(id: "1", text: "\"value\":", providerMetadata: nil),
        .textDelta(id: "1", text: "\"hi\"", providerMetadata: nil),
        .textDelta(id: "1", text: "}", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.json()
    )

    let partials = try await AsyncTestHelpers.collect(result.partialOutputStream)
    XCTAssertFalse(partials.isEmpty)
    XCTAssertEqual(partials.last, .object(["value": .string("hi")]))
  }

  func testPartialOutputStream_object() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "{", providerMetadata: nil),
        .textDelta(id: "1", text: "\"name\":", providerMetadata: nil),
        .textDelta(id: "1", text: "\"Ada\"", providerMetadata: nil),
        .textDelta(id: "1", text: "}", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.object(Person.self, schema: personSchema())
    )

    let partials = try await AsyncTestHelpers.collect(result.partialOutputStream)
    XCTAssertFalse(partials.isEmpty)
    XCTAssertEqual(partials.last, .object(["name": .string("Ada")]))
  }

  func testPartialOutputStream_array() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "{", providerMetadata: nil),
        .textDelta(id: "1", text: "\"elements\":[", providerMetadata: nil),
        .textDelta(id: "1", text: "{\"value\":\"a\"}", providerMetadata: nil),
        .textDelta(id: "1", text: ",", providerMetadata: nil),
        .textDelta(id: "1", text: "{\"value\":\"b\"}", providerMetadata: nil),
        .textDelta(id: "1", text: "]}", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.array(Item.self, elementSchema: itemSchema())
    )

    let partials = try await AsyncTestHelpers.collect(result.partialOutputStream)
    XCTAssertFalse(partials.isEmpty)
    XCTAssertEqual(partials.last, [Item(value: "a"), Item(value: "b")])
  }

  func testPartialOutputStream_choice() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "{", providerMetadata: nil),
        .textDelta(id: "1", text: "\"result\":", providerMetadata: nil),
        .textDelta(id: "1", text: "\"ap\"", providerMetadata: nil),
        .textDelta(id: "1", text: "}", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      output: Output.choice(options: ["apple", "banana"])
    )

    let partials = try await AsyncTestHelpers.collect(result.partialOutputStream)
    XCTAssertFalse(partials.isEmpty)
    XCTAssertEqual(partials.last, "apple")
  }

  func testStreamText_multiStepToolLoopAggregatesUsage() async throws {
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let usageStep1 = Usage(
      inputTokens: .init(total: 1, noCache: 1, cacheRead: nil, cacheWrite: nil),
      outputTokens: .init(total: 2, text: 2, reasoning: nil)
    )
    let usageStep2 = Usage(
      inputTokens: .init(total: 3, noCache: 3, cacheRead: nil, cacheWrite: nil),
      outputTokens: .init(total: 4, text: 4, reasoning: nil)
    )

    let queue = StreamQueue([
      makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: usageStep1, providerMetadata: nil),
      ]),
      makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Done.", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: usageStep2, providerMetadata: nil),
      ]),
    ])

    let model = makeModel { _ in
      queue.next()
    }

    let result = streamText(
      model: model,
      prompt: "test-input",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let steps = try await result.steps
    XCTAssertEqual(steps.count, 2)
    XCTAssertEqual(steps.first?.toolCalls.count, 1)
    XCTAssertEqual(steps.first?.toolResults.count, 1)
    let finalText = try await result.text
    XCTAssertEqual(finalText, "Done.")

    let totalUsage = try await result.totalUsage
    XCTAssertEqual(
      totalUsage,
      Usage(
        inputTokens: .init(total: 4, noCache: 4, cacheRead: nil, cacheWrite: nil),
        outputTokens: .init(total: 6, text: 6, reasoning: nil)
      )
    )
  }

  func testStreamText_onStepFinishAndOnFinishCallbacks() async throws {
    let usageStep1 = Usage(
      inputTokens: .init(total: 1, noCache: 1, cacheRead: nil, cacheWrite: nil),
      outputTokens: .init(total: 2, text: 2, reasoning: nil)
    )
    let usageStep2 = Usage(
      inputTokens: .init(total: 3, noCache: 3, cacheRead: nil, cacheWrite: nil),
      outputTokens: .init(total: 4, text: 4, reasoning: nil)
    )

    let queue = StreamQueue([
      makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .toolCalls, usage: usageStep1, providerMetadata: nil),
      ]),
      makeStream([
        .textStart(id: "2", providerMetadata: nil),
        .textDelta(id: "2", text: "World", providerMetadata: nil),
        .textEnd(id: "2", providerMetadata: nil),
        .finish(finishReason: .stop, usage: usageStep2, providerMetadata: nil),
      ]),
    ])

    let model = makeModel { _ in
      queue.next()
    }

    let stepFinishCount = CounterBox()
    let finishStepsCount = CounterBox()

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        stopWhen: [Stop.stepCountIs(2)],
        output: Output.text(),
        onStepFinish: { _ in
          stepFinishCount.increment()
        },
        onFinish: { event in
          finishStepsCount.set(event.steps.count)
        }
      )
    )

    _ = try await result.text
    XCTAssertEqual(stepFinishCount.get(), 2)
    XCTAssertEqual(finishStepsCount.get(), 2)
  }

  func testStreamText_onChunkReceivesExpectedParts() async throws {
    let recorder = ChunkRecorder()
    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let model = makeModel { _ in
      self.makeStream([
        .toolInputStart(id: "call-1", toolName: "testTool", providerMetadata: nil),
        .toolInputDelta(id: "call-1", delta: "{", providerMetadata: nil),
        .toolInputDelta(id: "call-1", delta: "\"value\":\"v\"}", providerMetadata: nil),
        .toolInputEnd(id: "call-1", providerMetadata: nil),
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"v\" }",
            providerExecuted: true,
            dynamic: true
          )
        ),
        .toolResult(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"v\" }",
            input: .object(["value": .string("v")]),
            output: .string("ok"),
            preliminary: false,
            providerExecuted: true,
            dynamic: true
          )
        ),
        .source(.init(
          sourceType: .url,
          id: "s1",
          url: "https://example.com",
          title: "Example",
          providerMetadata: nil
        )),
        .raw(.object(["key": .string("value")])),
        .textStart(id: "t1", providerMetadata: nil),
        .textDelta(id: "t1", text: "Hello", providerMetadata: nil),
        .textEnd(id: "t1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        includeRawParts: true,
        output: Output.text(),
        onChunk: { chunk in
          await recorder.append(chunk)
        }
      )
    )

    try await result.consumeStream()
    let chunks = await recorder.snapshot()

    XCTAssertEqual(
      chunks,
      [
        .toolInputStart(id: "call-1", toolName: "testTool", providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil),
        .toolInputDelta(id: "call-1", delta: "{", providerMetadata: nil),
        .toolInputDelta(id: "call-1", delta: "\"value\":\"v\"}", providerMetadata: nil),
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"v\" }",
            input: .object(["value": .string("v")]),
            invalid: nil,
            error: nil,
            providerExecuted: true,
            dynamic: true,
            title: nil,
            providerMetadata: nil
          )
        ),
        .toolResult(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"v\" }",
            input: .object(["value": .string("v")]),
            output: .string("ok"),
            preliminary: false,
            providerExecuted: true,
            dynamic: true,
            title: nil,
            providerMetadata: nil
          )
        ),
        .source(.init(
          sourceType: .url,
          id: "s1",
          url: "https://example.com",
          title: "Example",
          providerMetadata: nil
        )),
        .raw(.object(["key": .string("value")])),
        .textDelta(id: "t1", text: "Hello", providerMetadata: nil),
      ]
    )
  }

  func testStreamText_onErrorReceivesStreamErrors() async throws {
    let errorBox = CounterBox()
    let messageBox = MessageBox()

    let model = makeModel { _ in
      self.makeStream([
        .error(.init(message: "boom")),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text(),
        onError: { message in
          errorBox.increment()
          messageBox.set(message)
        }
      )
    )

    try await result.consumeStream()
    XCTAssertEqual(errorBox.get(), 1)
    XCTAssertEqual(messageBox.get(), "boom")
    let finishReason = try await result.finishReason
    XCTAssertEqual(finishReason, .error)
  }

  func testStreamText_onAbortEmitsAbortPart() async throws {
    let abortBox = CounterBox()
    let token = CancellationToken()
    await token.cancel()

    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        cancellationToken: token,
        output: Output.text(),
        onAbort: {
          abortBox.increment()
        }
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains(.abort))
    XCTAssertEqual(abortBox.get(), 1)
  }

  func testStreamText_toolInputCallbacks() async throws {
    let startBox = CounterBox()
    let deltaBox = CounterBox()
    let deltaMessageBox = MessageBox()

    var tools = ToolRegistry()
    tools.register(
      ToolID<ToolInput, String>("testTool"),
      ToolSpec(
        title: "Test Tool",
        inputSchema: .manual(
          jsonSchema: .object(
            properties: ["value": .string()],
            required: ["value"],
            additionalProperties: false
          ),
          name: "ToolInput"
        ),
        onInputStart: { _ in
          startBox.increment()
        },
        onInputDelta: { delta, _ in
          deltaBox.increment()
          deltaMessageBox.set(delta)
        },
        execute: { input, _ in
          .final("result for \(input.value)")
        }
      )
    )

    let model = makeModel { _ in
      self.makeStream([
        .toolInputStart(id: "call-1", toolName: "testTool", providerMetadata: nil),
        .toolInputDelta(id: "call-1", delta: "{\"value\":\"v\"}", providerMetadata: nil),
        .toolInputEnd(id: "call-1", providerMetadata: nil),
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"v\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        output: Output.text()
      )
    )

    try await result.consumeStream()
    XCTAssertEqual(startBox.get(), 1)
    XCTAssertEqual(deltaBox.get(), 1)
    XCTAssertEqual(deltaMessageBox.get(), "{\"value\":\"v\"}")
  }

  func testStreamText_providerExecutedToolInputStreaming() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .toolInputStart(
          id: "call-1",
          toolName: "serverTool",
          providerMetadata: nil,
          providerExecuted: true,
          dynamic: true,
          title: "Server Tool"
        ),
        .toolInputDelta(id: "call-1", delta: "{\"value\":\"v\"}", providerMetadata: nil),
        .toolInputEnd(id: "call-1", providerMetadata: nil),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text()
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains { part in
      guard case let .toolInputStart(id, toolName, _, providerExecuted, dynamic, title) = part else {
        return false
      }
      return id == "call-1"
        && toolName == "serverTool"
        && providerExecuted == true
        && dynamic == true
        && title == "Server Tool"
    })
  }

  func testStreamText_fullStreamEmitsErrorPart() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .error(.init(message: "boom")),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text()
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains(.error("boom")))
    let finishReason = try await result.finishReason
    XCTAssertEqual(finishReason, .error)
  }

  func testStreamText_abortMidStreamStopsFurtherText() async throws {
    let token = CancellationToken()

    let stream = AsyncThrowingStream(ModelStreamPart.self) { continuation in
      Task {
        continuation.yield(.textStart(id: "1", providerMetadata: nil))
        continuation.yield(.textDelta(id: "1", text: "Hello", providerMetadata: nil))
        try? await Task.sleep(nanoseconds: 20_000_000)
        await token.cancel()
        continuation.yield(.textDelta(id: "1", text: "World", providerMetadata: nil))
        continuation.yield(.textEnd(id: "1", providerMetadata: nil))
        continuation.finish()
      }
    }

    let model = makeModel { _ in stream }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        cancellationToken: token,
        output: Output.text()
      )
    )

    let text = try await AsyncTestHelpers.collect(result.textStream)
    XCTAssertEqual(text, ["Hello"])

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains(.abort))
  }

  func testStreamText_noOutputGeneratedThrows() async throws {
    let model = makeModel { _ in
      self.makeStream([])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text()
      )
    )

    do {
      _ = try await result.text
      XCTFail("Expected error")
    } catch let error as AIKitError {
      XCTAssertEqual(
        error,
        .invalidConfiguration("No output generated. Check the stream for errors.")
      )
    }
  }

  func testStreamText_transformModifiesText() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "hello", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let transform: StreamTextTransform = { input in
      AsyncThrowingStream(TextStreamPart.self) { continuation in
        Task {
          do {
            for try await part in input {
              switch part {
              case .textDelta(let id, let text, let providerMetadata):
                continuation.yield(.textDelta(id: id, text: text.uppercased(), providerMetadata: providerMetadata))
              default:
                continuation.yield(part)
              }
            }
            continuation.finish()
          } catch {
            continuation.finish(throwing: error)
          }
        }
      }
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        transform: transform,
        output: Output.text()
      )
    )

    let text = try await AsyncTestHelpers.collect(result.textStream)
    XCTAssertEqual(text, ["HELLO"])
    let finalText = try await result.text
    XCTAssertEqual(finalText, "HELLO")
    let steps = try await result.steps
    XCTAssertEqual(steps.last?.text, "HELLO")
  }

  func testStreamText_transformCanEndStreamEarly() async throws {
    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: nil),
        .textDelta(id: "1", text: " World", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let transform: StreamTextTransform = { input in
      AsyncThrowingStream(TextStreamPart.self) { continuation in
        Task {
          do {
            for try await part in input {
              continuation.yield(part)
              if case .textDelta = part {
                continuation.finish()
                break
              }
            }
          } catch {
            continuation.finish(throwing: error)
          }
        }
      }
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        transform: transform,
        output: Output.text()
      )
    )

    let text = try await AsyncTestHelpers.collect(result.textStream)
    XCTAssertEqual(text, ["Hello"])
  }

  func testStreamText_abortDuringToolExecution() async throws {
    let token = CancellationToken()

    let tools = toolRegistry(execute: { input, _ in
      let stream = AsyncThrowingStream<ToolProgress<String>, Error> { continuation in
        Task {
          continuation.yield(.preliminary("pre-\(input.value)"))
          try? await Task.sleep(nanoseconds: 20_000_000)
          continuation.yield(.final("final-\(input.value)"))
          continuation.finish()
        }
      }
      return .streaming(stream)
    })

    let model = makeModel { _ in
      self.makeStream([
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"value\" }"
          )
        ),
        .finish(finishReason: .toolCalls, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        tools: tools,
        cancellationToken: token,
        output: Output.text(),
        onChunk: { chunk in
          if case let .toolResult(result) = chunk, result.preliminary == true {
            await token.cancel()
          }
        }
      )
    )

    let events = try await AsyncTestHelpers.collect(result.fullStream)
    XCTAssertTrue(events.contains { part in
      guard case let .toolResult(result) = part else { return false }
      return result.preliminary == true
    })
    XCTAssertFalse(events.contains { part in
      guard case let .toolResult(result) = part else { return false }
      return result.preliminary == false
    })
    XCTAssertTrue(events.contains(.abort))
  }

  func testStreamText_providerMetadataPropagatesToContent() async throws {
    let metadata: ProviderMetadata = ["test": .string("value")]

    let model = makeModel { _ in
      self.makeStream([
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", text: "Hello", providerMetadata: metadata),
        .textEnd(id: "1", providerMetadata: nil),
        .toolCall(
          .init(
            toolCallID: "call-1",
            toolName: "testTool",
            inputJSON: "{ \"value\": \"v\" }",
            providerMetadata: metadata
          )
        ),
        .finish(finishReason: .stop, usage: self.usage, providerMetadata: nil),
      ])
    }

    let result = streamText(
      .init(
        model: model,
        prompt: "test-input",
        output: Output.text()
      )
    )

    let content = try await result.content
    let textPart = content.first
    if case let .text(text, providerMetadata) = textPart {
      XCTAssertEqual(text, "Hello")
      XCTAssertEqual(providerMetadata, metadata)
    } else {
      XCTFail("Expected text content")
    }

    let toolCalls = try await result.toolCalls
    XCTAssertEqual(toolCalls.first?.providerMetadata, metadata)
  }
}
