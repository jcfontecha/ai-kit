import XCTest
import AIKitProviders
import AIKitTestKit
@testable @_spi(Advanced) import AIKit

final class GenerateTextTests: XCTestCase {
  private struct ToolInput: Codable, Sendable, Equatable {
    let value: String
  }

  private struct EmptyOutput: Codable, Sendable, Equatable {}

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

  private func toolRegistryNoExecute(
    needsApproval: ToolNeedsApproval<ToolInput>? = nil
  ) -> ToolRegistry {
    var registry = ToolRegistry()
    registry.register(
      ToolID<ToolInput, EmptyOutput>("testTool"),
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
        execute: nil
      )
    )
    return registry
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

  private static func response(
    finishReason: FinishReason,
    content: [ModelContentPart],
    usage: Usage = .init()
  ) -> ModelResponse {
    .init(
      content: content,
      finishReason: finishReason,
      rawFinishReason: finishReason.rawValue,
      usage: usage,
      warnings: [],
      request: .init(),
      response: .init(),
      providerMetadata: nil
    )
  }

  func testGenerateText_basicText() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [.text("Hello, world!", metadata: nil)]
      ),
    ])

    let result = try await generateText(
      model: model,
      prompt: "Hi",
      output: Output.text()
    )

    XCTAssertEqual(result.text, "Hello, world!")
    XCTAssertEqual(try result.output, "Hello, world!")
    XCTAssertEqual(result.finishReason, .stop)
    XCTAssertEqual(result.steps.count, 1)
    XCTAssertEqual(result.responseMessages.count, 1)
  }

  func testGenerateText_toolCallExecutesAndLoops() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Done.", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    XCTAssertEqual(result.steps.count, 2)
    XCTAssertEqual(result.finishReason, .stop)
    XCTAssertEqual(result.text, "Done.")
    XCTAssertEqual(try result.output, "Done.")
    XCTAssertEqual(result.steps.first?.toolCalls.count, 1)
    XCTAssertEqual(result.steps.first?.toolResults.count, 1)
  }

  func testGenerateText_toolApprovalStopsAfterOneStep() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"needs-approval\" }"
            )
          ),
        ]
      ),
    ])

    let tools = toolRegistryNoExecute { _, _ in true }

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    XCTAssertEqual(result.steps.count, 1)
    XCTAssertEqual(result.finishReason, .toolCalls)
    let approvals = result.content.compactMap { part -> ToolApprovalRequest? in
      if case let .toolApprovalRequest(request) = part { return request }
      return nil
    }
    XCTAssertEqual(approvals.count, 1)
    XCTAssertEqual(approvals.first?.approvalID, "id-0")
  }

  func testGenerateText_invalidToolCallAddsErrorContentAndResponseMessages() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"bad\": \"value\" }"
            )
          ),
        ]
      ),
    ])

    let tools = toolRegistryNoExecute()

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      output: Output.text()
    )

    let toolErrors = result.content.compactMap { part -> ToolError? in
      if case let .toolError(error) = part { return error }
      return nil
    }
    XCTAssertEqual(toolErrors.count, 1)

    let assistantMessage = result.responseMessages.first
    XCTAssertEqual(assistantMessage?.role, .assistant)

    let toolMessage = result.responseMessages.last
    XCTAssertEqual(toolMessage?.role, .tool)
  }

  func testGenerateText_responseMessagesAggregatedAcrossSteps() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Final response", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    XCTAssertEqual(result.responseMessages.count, 3)
    XCTAssertEqual(result.responseMessages.first?.role, .assistant)
    XCTAssertEqual(result.responseMessages.dropFirst().first?.role, .tool)
    XCTAssertEqual(result.responseMessages.last?.role, .assistant)
  }

  func testGenerateText_toolCallsFromLastStepOnly() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Final response", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    XCTAssertEqual(result.steps.first?.toolCalls.count, 1)
    XCTAssertEqual(result.toolCalls.count, 0)
  }

  func testGenerateText_toolResultsFromLastStepOnly() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Final response", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    XCTAssertEqual(result.steps.first?.toolResults.count, 1)
    XCTAssertEqual(result.toolResults.count, 0)
  }

  func testGenerateText_usageAndTotalUsage() async throws {
    let usageStep1 = Usage(
      inputTokens: .init(total: 5, noCache: 5),
      outputTokens: .init(total: 7, text: 7)
    )
    let usageStep2 = Usage(
      inputTokens: .init(total: 2, noCache: 2),
      outputTokens: .init(total: 3, text: 3)
    )

    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ],
        usage: usageStep1
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Final response", metadata: nil),
        ],
        usage: usageStep2
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    XCTAssertEqual(result.usage, usageStep2)
    XCTAssertEqual(result.totalUsage.inputTokens?.total, 7)
    XCTAssertEqual(result.totalUsage.outputTokens?.total, 10)
  }

  func testGenerateText_headersForwardedToModelRequest() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [.text("Hello", metadata: nil)]
      ),
    ])

    let headers = ["x-test": "value", "x-extra": "1"]

    _ = try await generateText(
      model: model,
      prompt: "Test",
      headers: headers,
      output: Output.text()
    )

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?.headers ?? [:], headers)
  }

  func testGenerateText_providerOptionsForwardedToModelRequest() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [.text("Hello", metadata: nil)]
      ),
    ])

    let options: ProviderOptions = ["provider": ["option": .string("value")]]

    _ = try await generateText(
      model: model,
      prompt: "Test",
      providerOptions: options,
      output: Output.text()
    )

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?.providerOptions ?? [:], options)
  }

  func testGenerateText_abortSignalForwardedToModelRequest() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [.text("Hello", metadata: nil)]
      ),
    ])

    let token = CancellationToken()

    _ = try await generateText(
      model: model,
      prompt: "Test",
      cancellationToken: token,
      output: Output.text()
    )

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertTrue(requests.first?.cancellationToken === token)
  }

  func testGenerateText_activeToolsFiltersDefinitions() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [.text("Hello", metadata: nil)]
      ),
    ])

    struct OtherInput: Codable, Sendable, Equatable {
      let value: String
    }

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
        execute: { input, _ in .final("result for \(input.value)") }
      )
    )
    registry.register(
      ToolID<OtherInput, String>("otherTool"),
      ToolSpec(
        title: "Other Tool",
        inputSchema: .manual(
          jsonSchema: .object(
            properties: ["value": .string()],
            required: ["value"],
            additionalProperties: false
          ),
          name: "OtherInput"
        ),
        execute: { input, _ in .final("result for \(input.value)") }
      )
    )

    _ = try await generateText(
      model: model,
      prompt: "Test",
      tools: registry,
      activeTools: ["testTool"],
      output: Output.text()
    )

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    let toolNames = requests.first?.tools.map { $0.name } ?? []
    XCTAssertEqual(toolNames, ["testTool"])
  }

  func testGenerateText_requestResponseMetadataFromLastStep() async throws {
    let requestMetadata1 = LanguageModelRequestMetadata(body: .object(["step": .number(1)]))
    let responseMetadata1 = LanguageModelResponseMetadata(
      id: "r1",
      modelID: "model-a",
      timestamp: Date(timeIntervalSince1970: 123),
      headers: ["x-test": "step1"],
      body: .object(["step": .number(1)])
    )
    let requestMetadata2 = LanguageModelRequestMetadata(body: .object(["step": .number(2)]))
    let responseMetadata2 = LanguageModelResponseMetadata(
      id: "r2",
      modelID: "model-b",
      timestamp: Date(timeIntervalSince1970: 456),
      headers: ["x-test": "step2"],
      body: .object(["step": .number(2)])
    )

    let model = MockLanguageModel(responses: [
      .init(
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ],
        finishReason: .toolCalls,
        rawFinishReason: FinishReason.toolCalls.rawValue,
        usage: .init(),
        warnings: [],
        request: requestMetadata1,
        response: responseMetadata1,
        providerMetadata: nil
      ),
      .init(
        content: [
          .text("Final response", metadata: nil),
        ],
        finishReason: .stop,
        rawFinishReason: FinishReason.stop.rawValue,
        usage: .init(),
        warnings: [],
        request: requestMetadata2,
        response: responseMetadata2,
        providerMetadata: nil
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    XCTAssertEqual(result.request, requestMetadata2)
    XCTAssertEqual(result.response, responseMetadata2)
  }

  func testGenerateText_providerMetadataFromLastStep() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      .init(
        content: [
          .text("Final response", metadata: nil),
        ],
        finishReason: .stop,
        rawFinishReason: FinishReason.stop.rawValue,
        usage: .init(),
        warnings: [],
        request: .init(),
        response: .init(),
        providerMetadata: ["provider": .string("final-step")]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    XCTAssertEqual(result.providerMetadata, ["provider": JSONValue.string("final-step")])
  }

  func testGenerateText_toolExecutionErrorAddsToolErrorAndContinuesLoop() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Recovered.", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { _, _ in
      struct TestError: Error {}
      throw TestError()
    })

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let toolErrors = result.steps.first?.content.compactMap { part -> ToolError? in
      if case let .toolError(error) = part { return error }
      return nil
    } ?? []
    XCTAssertEqual(toolErrors.count, 1)
    XCTAssertTrue(toolErrors.first?.error.contains("Tool execution failed:") ?? false)
    XCTAssertEqual(result.steps.count, 2)
    XCTAssertEqual(result.text, "Recovered.")
  }

  func testGenerateText_onInputAvailableCalledEvenWhenApprovalRequired() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
    ])

    let onInputCalled = XCTestExpectation(description: "onInputAvailable called")

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
        needsApproval: { _, _ in true },
        onInputAvailable: { input, context in
          XCTAssertEqual(input, ToolInput(value: "value"))
          XCTAssertEqual(context.toolCallID, "call-1")
          onInputCalled.fulfill()
        },
        execute: nil
      )
    )

    _ = try await generateText(
      model: model,
      prompt: "Test",
      tools: registry,
      output: Output.text()
    )

    await fulfillment(of: [onInputCalled], timeout: 1.0)
  }

  func testGenerateText_needsApprovalReceivesContextMessages() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
    ])

    let messages: [ModelMessage] = [
      .user("User prompt")
    ]

    let approvalCalled = XCTestExpectation(description: "needsApproval called")

    let tools = toolRegistry(
      needsApproval: { input, context in
        XCTAssertEqual(input, ToolInput(value: "value"))
        XCTAssertEqual(context.toolCallID, "call-1")
        XCTAssertEqual(context.messages, messages)
        approvalCalled.fulfill()
        return true
      },
      execute: nil
    )

    _ = try await generateText(
      model: model,
      messages: messages,
      tools: tools,
      output: Output.text()
    )

    await fulfillment(of: [approvalCalled], timeout: 1.0)
  }

  func testGenerateText_providerExecutedToolIncludedAndNotExecuted() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .toolCall(
            .init(
              toolCallID: "provider-call-1",
              toolName: "providerTool",
              inputJSON: "{ \"value\": \"value\" }",
              providerExecuted: true,
              dynamic: true
            )
          ),
          .toolResult(
            .init(
              toolCallID: "provider-call-1",
              toolName: "providerTool",
              output: .object(["result": .string("ok")]),
              providerExecuted: true,
              dynamic: true
            )
          ),
        ]
      ),
    ])

    struct ProviderInput: Codable, Sendable, Equatable {
      let value: String
    }

    let executeCalled = XCTestExpectation(description: "execute should not be called")
    executeCalled.isInverted = true

    var registry = ToolRegistry()
    registry.register(
      ToolID<ProviderInput, String>("providerTool"),
      ToolSpec(
        title: "Provider Tool",
        inputSchema: .manual(
          jsonSchema: .object(
            properties: ["value": .string()],
            required: ["value"],
            additionalProperties: false
          ),
          name: "ProviderInput"
        ),
        execute: { _, _ in
          executeCalled.fulfill()
          return .final("client-executed")
        }
      )
    )

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: registry,
      output: Output.text()
    )

    let toolCalls = result.content.compactMap { part -> ToolCall? in
      if case let .toolCall(call) = part { return call }
      return nil
    }
    XCTAssertEqual(toolCalls.count, 1)
    XCTAssertEqual(toolCalls.first?.providerExecuted, true)

    let toolResults = result.content.compactMap { part -> ToolResult? in
      if case let .toolResult(result) = part { return result }
      return nil
    }
    XCTAssertEqual(toolResults.count, 1)
    XCTAssertEqual(toolResults.first?.providerExecuted, true)

    await fulfillment(of: [executeCalled], timeout: 0.2)
  }

  func testGenerateText_providerExecutedDeferredResultContinuesLoop() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "provider-call-1",
              toolName: "providerTool",
              inputJSON: "{ \"value\": \"value\" }",
              providerExecuted: true,
              dynamic: true
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .toolResult(
            .init(
              toolCallID: "provider-call-1",
              toolName: "providerTool",
              output: .object(["result": .string("ok")]),
              providerExecuted: true,
              dynamic: true
            )
          ),
          .text("Done", metadata: nil),
        ]
      ),
    ])

    struct ProviderInput: Codable, Sendable, Equatable {
      let value: String
    }

    var registry = ToolRegistry()
    registry.register(
      ToolID<ProviderInput, String>("providerTool"),
      ToolSpec(
        title: "Provider Tool",
        inputSchema: .manual(
          jsonSchema: .object(
            properties: ["value": .string()],
            required: ["value"],
            additionalProperties: false
          ),
          name: "ProviderInput"
        ),
        kind: .provider(supportsDeferredResults: true),
        execute: nil
      )
    )

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: registry,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    XCTAssertEqual(result.steps.count, 2)
    XCTAssertEqual(result.text, "Done")
  }

  func testGenerateText_programmaticToolCallingAcrossMultipleSteps() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .text("Starting game.", metadata: nil),
          .toolCall(
            .init(
              toolCallID: "code-exec-1",
              toolName: "code_execution",
              inputJSON: "{ \"code\": \"game_loop()\" }",
              providerExecuted: true
            )
          ),
          .toolCall(
            .init(
              toolCallID: "roll-1",
              toolName: "rollDie",
              inputJSON: "{ \"player\": \"player1\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "roll-2",
              toolName: "rollDie",
              inputJSON: "{ \"player\": \"player2\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .toolResult(
            .init(
              toolCallID: "code-exec-1",
              toolName: "code_execution",
              output: .object(["stdout": .string("done")]),
              providerExecuted: true
            )
          ),
          .text("Game complete.", metadata: nil),
        ]
      ),
    ])

    struct CodeInput: Codable, Sendable, Equatable {
      let code: String
    }

    struct RollInput: Codable, Sendable, Equatable {
      let player: String
    }

    actor RollRecorder {
      private var players: [String] = []
      func append(_ player: String) {
        players.append(player)
      }
      func snapshot() async -> [String] {
        players
      }
    }

    let rollRecorder = RollRecorder()

    var registry = ToolRegistry()
    registry.register(
      ToolID<CodeInput, String>("code_execution"),
      ToolSpec(
        title: "Code Execution",
        inputSchema: .manual(
          jsonSchema: .object(
            properties: ["code": .string()],
            required: ["code"],
            additionalProperties: false
          ),
          name: "CodeInput"
        ),
        kind: .provider(supportsDeferredResults: true),
        execute: nil
      )
    )
    registry.register(
      ToolID<RollInput, Int>("rollDie"),
      ToolSpec(
        title: "Roll Die",
        inputSchema: .manual(
          jsonSchema: .object(
            properties: ["player": .string()],
            required: ["player"],
            additionalProperties: false
          ),
          name: "RollInput"
        ),
        execute: { input, _ in
          await rollRecorder.append(input.player)
          return .final(6)
        }
      )
    )

    let result = try await generateText(
      model: model,
      prompt: "Play a game.",
      tools: registry,
      stopWhen: [Stop.stepCountIs(3)],
      output: Output.text()
    )

    XCTAssertEqual(result.steps.count, 3)
    XCTAssertEqual(result.text, "Game complete.")
    let rolls = await rollRecorder.snapshot()
    XCTAssertEqual(rolls, ["player1", "player2"])
  }

  func testGenerateText_messagesPassedToToolContext() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Done.", metadata: nil),
        ]
      ),
    ])

    let messages: [ModelMessage] = [
      .user("Message-based prompt")
    ]

    let contextExpectation = XCTestExpectation(description: "tool context includes messages")

    let tools = toolRegistry(execute: { input, context in
      XCTAssertEqual(input, ToolInput(value: "value"))
      XCTAssertEqual(context.messages, messages)
      contextExpectation.fulfill()
      return .final("ok")
    })

    _ = try await generateText(
      model: model,
      messages: messages,
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    await fulfillment(of: [contextExpectation], timeout: 1.0)
  }

  func testGenerateText_systemMessagePrependedToRequest() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text("Done.", metadata: nil),
        ]
      ),
    ])

    _ = try await generateText(
      model: model,
      system: .text("System instruction"),
      prompt: "User prompt",
      output: Output.text()
    )

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    let sentMessages = requests.first?.messages ?? []
    XCTAssertEqual(sentMessages.first?.role, .system)
    XCTAssertEqual(sentMessages.dropFirst().first?.role, .user)
  }

  func testGenerateText_stopWhenMultipleConditionsStopsWhenAnyTrue() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Should not reach", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let stopIfTwoSteps = Stop.stepCountIs(2)
    let stopImmediately: StopCondition = { _ in true }

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [stopIfTwoSteps, stopImmediately],
      output: Output.text()
    )

    XCTAssertEqual(result.steps.count, 1)
    XCTAssertEqual(result.finishReason, .toolCalls)
  }

  func testGenerateText_stopWhenEvaluatedEachStep() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Second step", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    actor EvaluationRecorder {
      private var values: [Int] = []
      func append(_ value: Int) {
        values.append(value)
      }
      func snapshot() async -> [Int] {
        values
      }
    }

    let recorder = EvaluationRecorder()

    let condition: StopCondition = { steps in
      await recorder.append(steps.count)
      return steps.count == 2
    }

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [condition],
      output: Output.text()
    )

    XCTAssertEqual(result.steps.count, 2)
    XCTAssertEqual(result.text, "Second step")
    let evaluations = await recorder.snapshot()
    XCTAssertEqual(evaluations, [1, 2])
  }

  func testGenerateText_prepareStepOverridesProviderOptionsAndMessages() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Second step", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    _ = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      prepareStep: { context in
        if context.stepNumber == 1 {
          return .init(
            messages: [.user("override messages")],
            providerOptions: ["provider": ["option": .string("override")]]
          )
        }
        return nil
      },
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(requests.last?.messages.first?.role, .user)
    XCTAssertEqual(requests.last?.messages.first?.content.count, 1)
    XCTAssertEqual(requests.last?.providerOptions ?? [:], ["provider": ["option": .string("override")]])
  }

  func testGenerateText_prepareStepOverridesToolsAndActiveTools() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Second step", metadata: nil),
        ]
      ),
    ])

    struct OtherInput: Codable, Sendable, Equatable {
      let value: String
    }

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
        execute: { input, _ in .final("result for \(input.value)") }
      )
    )
    registry.register(
      ToolID<OtherInput, String>("otherTool"),
      ToolSpec(
        title: "Other Tool",
        inputSchema: .manual(
          jsonSchema: .object(
            properties: ["value": .string()],
            required: ["value"],
            additionalProperties: false
          ),
          name: "OtherInput"
        ),
        execute: { input, _ in .final("result for \(input.value)") }
      )
    )

    _ = try await generateText(
      model: model,
      prompt: "Test",
      tools: registry,
      prepareStep: { context in
        if context.stepNumber == 1 {
          return .init(
            activeTools: ["otherTool"]
          )
        }
        return nil
      },
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 2)
    let toolNames = requests.last?.tools.map(\.name) ?? []
    XCTAssertEqual(toolNames, ["otherTool"])
  }

  func testGenerateText_onStepFinishCalledForEachStep() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Second step", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    actor StepRecorder {
      private var finishes: [StepResult] = []
      func append(_ step: StepResult) { finishes.append(step) }
      func snapshot() async -> [StepResult] { finishes }
    }

    let recorder = StepRecorder()

    _ = try await generateText(.init(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text(),
      onStepFinish: { step in
        await recorder.append(step)
      }
    ))

    let finishes = await recorder.snapshot()
    XCTAssertEqual(finishes.count, 2)
    XCTAssertEqual(finishes.first?.finishReason, .toolCalls)
    XCTAssertEqual(finishes.last?.finishReason, .stop)
  }

  func testGenerateText_onFinishPayloadMatchesResult() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text("Done", metadata: nil),
        ],
        usage: Usage(
          inputTokens: .init(total: 1, noCache: 1),
          outputTokens: .init(total: 2, text: 2)
        )
      ),
    ])

    let expectation = XCTestExpectation(description: "onFinish called")
    actor FinishRecorder {
      private var event: GenerateTextFinishEvent<Output.Text>?
      func set(_ value: GenerateTextFinishEvent<Output.Text>) { event = value }
      func snapshot() async -> GenerateTextFinishEvent<Output.Text>? { event }
    }

    let recorder = FinishRecorder()

    let result = try await generateText(.init(
      model: model,
      prompt: "Test",
      output: Output.text(),
      experimentalContext: AnySendable("context"),
      onFinish: { event in
        await recorder.set(event)
        expectation.fulfill()
      }
    ))

    await fulfillment(of: [expectation], timeout: 1.0)
    guard let event = await recorder.snapshot() else {
      XCTFail("Missing onFinish event")
      return
    }

    XCTAssertEqual(event.finishReason, result.finishReason)
    XCTAssertEqual(event.totalUsage, result.totalUsage)
    XCTAssertEqual(event.steps.count, result.steps.count)
    XCTAssertEqual(event.output, try? result.output)
    XCTAssertEqual(event.experimentalContext?.value as? String, "context")
  }

  func testGenerateText_resultSurfaceReasoningAndToolParts() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text("Hello", metadata: nil),
          .reasoning("because", metadata: nil),
          .toolResult(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              output: .object(["value": .string("ok")])
            )
          ),
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
          .toolError(
            .init(
              toolCallID: "call-2",
              toolName: "testTool",
              error: "err"
            )
          ),
        ]
      ),
    ])

    let result = try await generateText(
      model: model,
      prompt: "Test",
      output: Output.text()
    )

    XCTAssertEqual(result.text, "Hello")
    XCTAssertEqual(result.reasoningText, "because")
    XCTAssertEqual(result.toolCalls.count, 1)
    XCTAssertEqual(result.toolResults.count, 1)
  }

  func testGenerateText_outputTextForwardsTextAndSetsResponseFormat() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [.text("Hello, world!", metadata: nil)]
      ),
    ])

    let result = try await generateText(
      model: model,
      prompt: "prompt",
      output: Output.text()
    )

    XCTAssertEqual(result.text, "Hello, world!")
    XCTAssertEqual(try result.output, "Hello, world!")

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?.responseFormat, .text)
    XCTAssertEqual(requests.first?.messages.first?.role, .user)
  }

  func testGenerateText_outputObjectParsesAndSetsResponseFormat() async throws {
    struct Payload: Codable, Sendable, Equatable {
      let value: String
    }

    let schema = ObjectSchema<Payload>.manual(
      jsonSchema: .object(
        properties: ["value": .string()],
        required: ["value"],
        additionalProperties: false
      ),
      name: "Payload"
    )

    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [.text("{ \"value\": \"test-value\" }", metadata: nil)]
      ),
    ])

    let output = Output.object(Payload.self, schema: schema)
    let result = try await generateText(
      model: model,
      prompt: "prompt",
      output: output
    )

    XCTAssertEqual(try result.output, Payload(value: "test-value"))

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?.responseFormat, output.responseFormat)
  }

  func testGenerateText_outputArrayParsesAndSetsResponseFormat() async throws {
    struct Item: Codable, Sendable, Equatable {
      let content: String
    }

    let elementSchema = ObjectSchema<Item>.manual(
      jsonSchema: .object(
        properties: ["content": .string()],
        required: ["content"],
        additionalProperties: false
      ),
      name: "Item"
    )

    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text(
            """
            { "elements": [ { "content": "element 1" }, { "content": "element 2" } ] }
            """,
            metadata: nil
          ),
        ]
      ),
    ])

    let output = Output.array(Item.self, elementSchema: elementSchema)
    let result = try await generateText(
      model: model,
      prompt: "prompt",
      output: output
    )

    XCTAssertEqual(try result.output, [Item(content: "element 1"), Item(content: "element 2")])

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?.responseFormat, output.responseFormat)
  }

  func testGenerateText_outputChoiceParsesAndSetsResponseFormat() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text("{ \"result\": \"sunny\" }", metadata: nil),
        ]
      ),
    ])

    let output = Output.choice(options: ["sunny", "rainy", "snowy"])
    let result = try await generateText(
      model: model,
      prompt: "prompt",
      output: output
    )

    XCTAssertEqual(try result.output, "sunny")

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?.responseFormat, output.responseFormat)
  }

  func testGenerateText_doesNotParseOutputWhenFinishReasonIsToolCalls() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    struct Summary: Codable, Sendable, Equatable {
      let summary: String
    }

    let schema = ObjectSchema<Summary>.manual(
      jsonSchema: .object(
        properties: ["summary": .string()],
        required: ["summary"],
        additionalProperties: false
      ),
      name: "Summary"
    )

    let output = Output.object(Summary.self, schema: schema)
    let result = try await generateText(
      model: model,
      prompt: "prompt",
      tools: tools,
      output: output
    )

    XCTAssertThrowsError(try result.output)
    XCTAssertEqual(result.toolCalls.count, 1)
    XCTAssertEqual(result.toolResults.count, 1)
  }

  func testGenerateText_resultSourcesAndFiles() async throws {
    let source = Source(
      sourceType: .url,
      id: "src-1",
      url: "https://example.com",
      title: "Example"
    )
    let file = GeneratedFile(data: Data([0x01, 0x02]), mediaType: "image/png")

    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text("Hello", metadata: nil),
          .source(source),
          .file(file),
        ]
      ),
    ])

    let result = try await generateText(
      model: model,
      prompt: "prompt",
      output: Output.text()
    )

    XCTAssertEqual(result.sources, [source])
    XCTAssertEqual(result.files, [file])
  }

  func testGenerateText_systemAsMessagePreserved() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text("Done", metadata: nil),
        ]
      ),
    ])

    let systemMessage = ModelMessage(role: .system, content: [.text("System message")])

    _ = try await generateText(
      model: model,
      system: .message(systemMessage),
      prompt: "User prompt",
      output: Output.text()
    )

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    let messages = requests.first?.messages ?? []
    XCTAssertEqual(messages.first?.role, .system)
    XCTAssertEqual(messages.dropFirst().first?.role, .user)
  }

  func testGenerateText_systemAsMessagesArrayPreserved() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text("Done", metadata: nil),
        ]
      ),
    ])

    let systemMessages = [
      ModelMessage(role: .system, content: [.text("System 1")]),
      ModelMessage(role: .system, content: [.text("System 2")]),
    ]

    _ = try await generateText(
      model: model,
      system: .messages(systemMessages),
      prompt: "User prompt",
      output: Output.text()
    )

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    let messages = requests.first?.messages ?? []
    XCTAssertEqual(messages.first?.role, .system)
    XCTAssertEqual(messages.dropFirst().first?.role, .system)
    XCTAssertEqual(messages.dropFirst(2).first?.role, .user)
  }

  func testGenerateText_toolsWithCustomSchemaPassedToModel() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "tool1",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
    ])

    struct Tool1Input: Codable, Sendable, Equatable {
      let value: String
    }
    struct Tool2Input: Codable, Sendable, Equatable {
      let somethingElse: String
    }

    var registry = ToolRegistry()
    registry.register(
      ToolID<Tool1Input, String>("tool1"),
      ToolSpec(
        inputSchema: .manual(
          jsonSchema: .object(
            properties: ["value": .string()],
            required: ["value"],
            additionalProperties: false
          ),
          name: "Tool1Input"
        ),
        execute: nil
      )
    )
    registry.register(
      ToolID<Tool2Input, String>("tool2"),
      ToolSpec(
        inputSchema: .manual(
          jsonSchema: .object(
            properties: ["somethingElse": .string()],
            required: ["somethingElse"],
            additionalProperties: false
          ),
          name: "Tool2Input"
        ),
        execute: nil
      )
    )

    let result = try await generateText(
      model: model,
      prompt: "test-input",
      tools: registry,
      toolChoice: .required,
      output: Output.text()
    )

    let requests = model.recordedRequests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests.first?.toolChoice, .required)
    XCTAssertEqual(requests.first?.messages.first?.role, .user)

    XCTAssertEqual(requests.first?.tools, registry.definitions)

    XCTAssertEqual(result.toolCalls.count, 1)
    XCTAssertEqual(result.toolCalls.first?.toolName, "tool1")
  }

  func testGenerateText_resultContentIncludesAllPartsWithMetadata() async throws {
    let source = Source(
      sourceType: .url,
      id: "123",
      url: "https://example.com",
      title: "Example",
      providerMetadata: ["provider": .object(["custom": .string("value")])]
    )
    let file = GeneratedFile(data: Data([1, 2, 3]), mediaType: "image/png")

    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .text("Hello, world!", metadata: nil),
          .source(source),
          .file(file),
          .reasoning("I will open the conversation with witty banter.", metadata: nil),
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
          .text("More text", metadata: nil),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Final", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result1")
    })

    let result = try await generateText(
      model: model,
      prompt: "prompt",
      tools: tools,
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    let content = result.steps.first?.content ?? []
    XCTAssertEqual(content.count, 7)
    XCTAssertEqual(result.sources, [source])
    XCTAssertEqual(result.files, [file])

    let toolResults = content.compactMap { part -> ToolResult? in
      if case let .toolResult(result) = part { return result }
      return nil
    }
    XCTAssertEqual(toolResults.count, 1)
    XCTAssertEqual(toolResults.first?.output, .string("result1"))
  }

  func testGenerateText_outputParseFailureThrowsNoObjectGeneratedError() async throws {
    struct Payload: Codable, Sendable, Equatable {
      let value: String
    }

    let schema = ObjectSchema<Payload>.manual(
      jsonSchema: .object(
        properties: ["value": .string()],
        required: ["value"],
        additionalProperties: false
      ),
      name: "Payload"
    )

    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [.text("{ \"wrong\": \"value\" }", metadata: nil)]
      ),
    ])

    let result = try await generateText(
      model: model,
      prompt: "prompt",
      output: Output.object(Payload.self, schema: schema)
    )

    XCTAssertThrowsError(try result.output) { error in
      guard let noObject = error as? NoObjectGeneratedError else {
        return XCTFail("Expected NoObjectGeneratedError")
      }
      XCTAssertEqual(noObject.finishReason, .stop)
    }
  }

  func testGenerateText_approvalApprovedIncludesToolResultInResponseMessages() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text("Hello, world!", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(needsApproval: { _, _ in true }, execute: { input, _ in
      .final("result for \(input.value)")
    })

    let messages: [ModelMessage] = [
      .user("test-input"),
      .init(
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
          .toolApprovalRequest(.init(approvalID: "id-0", toolCallID: "call-1")),
        ]
      ),
      .init(
        role: .tool,
        content: [
          .toolApprovalResponse(.init(approvalID: "id-0", approved: true)),
        ]
      ),
    ]

    let result = try await generateText(
      model: model,
      messages: messages,
      tools: tools,
      output: Output.text()
    )

    XCTAssertEqual(result.responseMessages.first?.role, .tool)
    XCTAssertEqual(result.responseMessages.last?.role, .assistant)

    let toolResults = result.responseMessages.first?.content.compactMap { part -> ToolResult? in
      if case let .toolResult(result) = part { return result }
      return nil
    } ?? []
    XCTAssertEqual(toolResults.count, 1)
  }

  func testGenerateText_approvalDeniedIncludesToolOutputDeniedInResponseMessages() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .text("Hello, world!", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(needsApproval: { _, _ in true }, execute: { input, _ in
      .final("result for \(input.value)")
    })

    let messages: [ModelMessage] = [
      .user("test-input"),
      .init(
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
          .toolApprovalRequest(.init(approvalID: "id-0", toolCallID: "call-1")),
        ]
      ),
      .init(
        role: .tool,
        content: [
          .toolApprovalResponse(.init(approvalID: "id-0", approved: false)),
        ]
      ),
    ]

    let result = try await generateText(
      model: model,
      messages: messages,
      tools: tools,
      output: Output.text()
    )

    XCTAssertEqual(result.responseMessages.first?.role, .tool)
    let deniedResults = result.responseMessages.first?.content.compactMap { part -> ToolResult? in
      if case let .toolResult(result) = part { return result }
      return nil
    } ?? []
    XCTAssertEqual(deniedResults.count, 1)
    XCTAssertEqual(deniedResults.first?.output, .object([
      "type": .string("error-text"),
      "value": .string("Tool execution denied."),
    ]))
  }

  func testGenerateText_stopWhenOverridesToolLoop() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
      Self.response(
        finishReason: .stop,
        content: [
          .text("Should not reach", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let result = try await generateText(
      model: model,
      prompt: "Test",
      tools: tools,
      stopWhen: [Stop.stepCountIs(1)],
      output: Output.text()
    )

    XCTAssertEqual(result.steps.count, 1)
    XCTAssertEqual(result.finishReason, .toolCalls)
  }

  func testGenerateText_prepareStepCanOverrideModelAndSystem() async throws {
    let modelA = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "call-1",
              toolName: "testTool",
              inputJSON: "{ \"value\": \"value\" }"
            )
          ),
        ]
      ),
    ])

    let modelB = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text("Second step", metadata: nil),
        ]
      ),
    ])

    let tools = toolRegistry(execute: { input, _ in
      .final("result for \(input.value)")
    })

    let result = try await generateText(
      model: modelA,
      prompt: "Test",
      tools: tools,
      prepareStep: { context in
        if context.stepNumber == 1 {
          return .init(
            model: modelB,
            system: .text("override-system")
          )
        }
        return nil
      },
      stopWhen: [Stop.stepCountIs(2)],
      output: Output.text()
    )

    XCTAssertEqual(result.steps.count, 2)
    XCTAssertEqual(result.text, "Second step")

    let requestsB = modelB.recordedRequests()
    XCTAssertEqual(requestsB.count, 1)
    let systemMessage = requestsB.first?.messages.first
    XCTAssertEqual(systemMessage?.role, .system)
  }

  func testGenerateText_prepareStepUsesModelSupportedURLsForDownload() async throws {
    let downloadBox = DownloadRequestsBox()
    let requestBox = RequestBox()

    let modelWithSupport = MockLanguageModel(
      supportedURLs: [
        "image/*": [URLPattern("^https?:\\/\\/.*$")]
      ],
      responses: [
        Self.response(finishReason: .stop, content: [.text("ignored", metadata: nil)]),
      ]
    )

    let modelWithoutSupport = MockLanguageModel(
      supportedURLs: [:],
      generate: { request in
        requestBox.set(request)
        return Self.response(
          finishReason: .stop,
          content: [.text("response from without-image-url-support", metadata: nil)]
        )
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

    let result = try await generateText(
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

    XCTAssertEqual(result.text, "response from without-image-url-support")

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

  func testGenerateText_imageDataURLConvertsToBase64AndMediaType() async throws {
    let requestBox = RequestBox()
    let dataURL = URL(string: "data:image/png;base64,QUJDRA==")!

    let model = MockLanguageModel(
      generate: { request in
        requestBox.set(request)
        return Self.response(
          finishReason: .stop,
          content: [.text("ok", metadata: nil)]
        )
      }
    )

    let result = try await generateText(
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

    XCTAssertEqual(result.text, "ok")

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

  func testGenerateText_filePartRequiresMediaType() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(finishReason: .stop, content: [.text("ok", metadata: nil)]),
    ])

    do {
      _ = try await generateText(
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
      XCTFail("Expected missing media type error")
    } catch {
      XCTAssertEqual(
        String(describing: error),
        "invalidConfiguration(\"Media type is missing for file part.\")"
      )
    }
  }

  func testGenerateText_fileURLSupportedPassesThroughWithoutDownload() async throws {
    let requestBox = RequestBox()
    let downloadBox = DownloadRequestsBox()

    let model = MockLanguageModel(
      supportedURLs: [
        "application/pdf": [URLPattern("^https?:\\/\\/.*$")]
      ],
      generate: { request in
        requestBox.set(request)
        return Self.response(
          finishReason: .stop,
          content: [.text("ok", metadata: nil)]
        )
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

    let result = try await generateText(
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

    XCTAssertEqual(result.text, "ok")

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

  func testGenerateText_fileURLUnsupportedDownloadsData() async throws {
    let requestBox = RequestBox()
    let downloadBox = DownloadRequestsBox()

    let model = MockLanguageModel(
      supportedURLs: [:],
      generate: { request in
        requestBox.set(request)
        return Self.response(
          finishReason: .stop,
          content: [.text("ok", metadata: nil)]
        )
      }
    )

    let download: DownloadFunction = { requests in
      downloadBox.set(requests)
      return requests.map { _ in
        DownloadedAsset(data: Data([9, 9, 9]), mediaType: "application/pdf")
      }
    }

    let result = try await generateText(
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

    XCTAssertEqual(result.text, "ok")

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

  func testGenerateText_fileURLMissingMediaTypeThrowsEvenWithDownload() async throws {
    let downloadBox = DownloadRequestsBox()

    let model = MockLanguageModel(
      supportedURLs: [:],
      generate: { _ in
        Self.response(
          finishReason: .stop,
          content: [.text("ok", metadata: nil)]
        )
      }
    )

    let download: DownloadFunction = { requests in
      downloadBox.set(requests)
      return requests.map { _ in
        DownloadedAsset(data: Data([9, 9, 9]), mediaType: "application/pdf")
      }
    }

    do {
      _ = try await generateText(
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
      XCTFail("Expected missing media type error")
    } catch {
      XCTAssertEqual(
        String(describing: error),
        "invalidConfiguration(\"Media type is missing for file part.\")"
      )
    }
  }

  func testGenerateText_imageMediaTypeDetectionOverridesProvided() async throws {
    let requestBox = RequestBox()
    let pngBase64 = "iVBORw0KGgo="

    let model = MockLanguageModel(
      generate: { request in
        requestBox.set(request)
        return Self.response(
          finishReason: .stop,
          content: [.text("ok", metadata: nil)]
        )
      }
    )

    let result = try await generateText(
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

    XCTAssertEqual(result.text, "ok")

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

  func testGenerateText_supportedURLsWildcardMatchesAnyMediaType() async throws {
    let downloadBox = DownloadRequestsBox()

    let model = MockLanguageModel(
      supportedURLs: [
        "*/*": [URLPattern("^https?:\\/\\/.*$")]
      ],
      generate: { _ in
        Self.response(
          finishReason: .stop,
          content: [.text("ok", metadata: nil)]
        )
      }
    )

    let download: DownloadFunction = { requests in
      downloadBox.set(requests)
      return requests.map { _ in nil }
    }

    let result = try await generateText(
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

    XCTAssertEqual(result.text, "ok")

    let downloadRequests = downloadBox.get()
    XCTAssertEqual(downloadRequests.count, 1)
    XCTAssertEqual(downloadRequests.first?.isURLSupportedByModel, true)
  }

  func testGenerateText_filtersEmptyTextPartsInUserMixedContent() async throws {
    let requestBox = RequestBox()

    let model = MockLanguageModel(
      generate: { request in
        requestBox.set(request)
        return Self.response(
          finishReason: .stop,
          content: [.text("ok", metadata: nil)]
        )
      }
    )

    let result = try await generateText(
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

    XCTAssertEqual(result.text, "ok")

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

  func testGenerateText_filtersEmptyTextPartsInAssistantContent() async throws {
    let requestBox = RequestBox()

    let model = MockLanguageModel(
      generate: { request in
        requestBox.set(request)
        return Self.response(
          finishReason: .stop,
          content: [.text("ok", metadata: nil)]
        )
      }
    )

    let result = try await generateText(
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

    XCTAssertEqual(result.text, "ok")

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

  func testGenerateText_imageWildcardMatchesButImagePngDoesNotForJpeg() async throws {
    let downloadBox = DownloadRequestsBox()

    let model = MockLanguageModel(
      supportedURLs: [
        "image/*": [URLPattern("^https?:\\/\\/example\\.com\\/.*$")],
        "image/png": [URLPattern("^https?:\\/\\/png-only\\.com\\/.*$")]
      ],
      generate: { _ in
        Self.response(
          finishReason: .stop,
          content: [.text("ok", metadata: nil)]
        )
      }
    )

    let download: DownloadFunction = { requests in
      downloadBox.set(requests)
      return requests.map { _ in nil }
    }

    let result = try await generateText(
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

    XCTAssertEqual(result.text, "ok")

    let downloadRequests = downloadBox.get()
    XCTAssertEqual(downloadRequests.count, 1)
    XCTAssertEqual(downloadRequests.first?.isURLSupportedByModel, true)
  }

  func testGenerateText_providerExecutedApprovalRequestIncluded() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .toolCalls,
        content: [
          .toolCall(
            .init(
              toolCallID: "mcp-call-1",
              toolName: "mcp_tool",
              inputJSON: "{ \"value\": \"value\" }",
              providerExecuted: true
            )
          ),
          .toolApprovalRequest(.init(approvalID: "mcp-approval-1", toolCallID: "mcp-call-1")),
        ]
      ),
    ])

    let result = try await generateText(
      model: model,
      prompt: "Test",
      output: Output.text()
    )

    let approvals = result.content.compactMap { part -> ToolApprovalRequest? in
      if case let .toolApprovalRequest(request) = part { return request }
      return nil
    }
    XCTAssertEqual(approvals.count, 1)
    XCTAssertEqual(approvals.first?.toolCall?.toolCallID, "mcp-call-1")
    XCTAssertEqual(result.finishReason, .toolCalls)
  }

  func testGenerateText_providerExecutedApprovalDoesNotEmitToolOutputDenied() async throws {
    let model = MockLanguageModel(responses: [
      Self.response(
        finishReason: .stop,
        content: [
          .text("Done", metadata: nil),
        ]
      ),
    ])

    let messages: [ModelMessage] = [
      .user("test-input"),
      .init(
        role: .assistant,
        content: [
          .toolCall(
            .init(
              toolCallID: "mcp-call-1",
              toolName: "mcp_tool",
              inputJSON: "{ \"value\": \"value\" }",
              input: .object(["value": .string("value")]),
              providerExecuted: true
            )
          ),
          .toolApprovalRequest(.init(approvalID: "mcp-approval-1", toolCallID: "mcp-call-1")),
        ]
      ),
      .init(
        role: .tool,
        content: [
          .toolApprovalResponse(.init(approvalID: "mcp-approval-1", approved: false)),
        ]
      ),
    ]

    let result = try await generateText(
      model: model,
      messages: messages,
      output: Output.text()
    )

    let denied = result.responseMessages.flatMap { $0.content }.compactMap { part -> ToolResult? in
      if case let .toolResult(result) = part, result.output == .object([
        "type": .string("error-text"),
        "value": .string("Tool execution denied."),
      ]) {
        return result
      }
      return nil
    }
    XCTAssertEqual(denied.count, 0)
  }
}
