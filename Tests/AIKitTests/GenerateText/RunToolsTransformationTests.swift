import XCTest
import AIKitProviders
import AIKitTestKit
@testable @_spi(Advanced) import AIKit

final class RunToolsTransformationTests: XCTestCase {
  private struct ValueInput: Codable, Sendable, Equatable {
    let value: String
  }

  private struct QueryInput: Codable, Sendable, Equatable {
    let query: String
  }

  private struct CommandInput: Codable, Sendable, Equatable {
    let command: String
  }

  private struct NoOutput: Codable, Sendable, Equatable {}

  private final class IDGeneratorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var next: Int
    private let prefix: String

    init(prefix: String = "id", startAt: Int = 0) {
      self.prefix = prefix
      self.next = startAt
    }

    func generate() -> String {
      lock.lock()
      defer { lock.unlock() }
      let value = "\(prefix)-\(next)"
      next += 1
      return value
    }
  }

  private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool = false) {
      self.value = value
    }

    func set(_ newValue: Bool) {
      lock.lock()
      defer { lock.unlock() }
      value = newValue
    }

    func get() -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  private struct ToolCallSnapshot: Equatable {
    let toolCallID: String
    let toolName: String
    let input: JSONValue?
    let providerExecuted: Bool?
    let dynamic: Bool?
    let title: String?

    init(_ call: ToolCall) {
      toolCallID = call.toolCallID
      toolName = call.toolName
      input = call.input
      providerExecuted = call.providerExecuted
      dynamic = call.dynamic
      title = call.title
    }
  }

  private struct ToolResultSnapshot: Equatable {
    let toolCallID: String
    let toolName: String
    let input: JSONValue?
    let output: JSONValue
    let preliminary: Bool?
    let providerExecuted: Bool?
    let dynamic: Bool?
    let title: String?

    init(_ result: ToolResult) {
      toolCallID = result.toolCallID
      toolName = result.toolName
      input = result.input
      output = result.output
      preliminary = result.preliminary
      providerExecuted = result.providerExecuted
      dynamic = result.dynamic
      title = result.title
    }
  }

  private struct ToolApprovalRequestSnapshot: Equatable {
    let approvalID: String
    let toolCallID: String
    let toolCall: ToolCallSnapshot?

    init(_ request: ToolApprovalRequest) {
      approvalID = request.approvalID
      toolCallID = request.toolCallID
      toolCall = request.toolCall.map(ToolCallSnapshot.init)
    }
  }

  private enum Event: Equatable {
    case textStart(String)
    case textDelta(String, String)
    case textEnd(String)
    case toolCall(ToolCallSnapshot)
    case toolResult(ToolResultSnapshot)
    case toolApprovalRequest(ToolApprovalRequestSnapshot)
    case finish(FinishReason, Usage, String?)
    case onInputAvailable(JSONValue)
    case error(String)
  }

  private actor EventRecorder {
    private var events: [Event] = []

    func append(_ event: Event) {
      events.append(event)
    }

    func snapshot() -> [Event] {
      events
    }
  }

  private let usage = Usage(
    inputTokens: .init(total: 3, noCache: 3, cacheRead: nil, cacheWrite: nil),
    outputTokens: .init(total: 10, text: 10, reasoning: nil)
  )

  private func makeStream(
    _ parts: [ModelStreamPart]
  ) -> AsyncThrowingStream<ModelStreamPart, Error> {
    AsyncThrowingStream(ModelStreamPart.self) { continuation in
      for part in parts {
        continuation.yield(part)
      }
      continuation.finish()
    }
  }

  private func schemaForValueInput() -> ObjectSchema<ValueInput> {
    .manual(
      jsonSchema: .object(
        properties: ["value": .string()],
        required: ["value"],
        additionalProperties: false
      ),
      name: "ValueInput"
    )
  }

  private func schemaForQueryInput() -> ObjectSchema<QueryInput> {
    .manual(
      jsonSchema: .object(
        properties: ["query": .string()],
        required: ["query"],
        additionalProperties: false
      ),
      name: "QueryInput"
    )
  }

  private func schemaForCommandInput() -> ObjectSchema<CommandInput> {
    .manual(
      jsonSchema: .object(
        properties: ["command": .string()],
        required: ["command"],
        additionalProperties: false
      ),
      name: "CommandInput"
    )
  }

  private func registryForTool<Input: Codable & Sendable, Output: Codable & Sendable>(
    name: String,
    title: String? = nil,
    inputSchema: ObjectSchema<Input>,
    needsApproval: ToolNeedsApproval<Input>? = nil,
    onInputAvailable: (@Sendable (_ input: Input, _ context: ToolContext) async -> Void)? = nil,
    execute: (@Sendable (_ input: Input, _ context: ToolContext) async throws -> ToolExecution<Output>)? = nil
  ) -> ToolRegistry {
    var registry = ToolRegistry()
    registry.register(
      ToolID<Input, Output>(name),
      ToolSpec(
        title: title,
        inputSchema: inputSchema,
        needsApproval: needsApproval,
        onInputAvailable: onInputAvailable,
        execute: execute
      )
    )
    return registry
  }

  private func registryForTool<Input: Codable & Sendable>(
    name: String,
    title: String? = nil,
    inputSchema: ObjectSchema<Input>,
    needsApproval: ToolNeedsApproval<Input>? = nil,
    onInputAvailable: (@Sendable (_ input: Input, _ context: ToolContext) async -> Void)? = nil
  ) -> ToolRegistry {
    var registry = ToolRegistry()
    registry.register(
      ToolID<Input, NoOutput>(name),
      ToolSpec(
        title: title,
        inputSchema: inputSchema,
        needsApproval: needsApproval,
        onInputAvailable: onInputAvailable,
        execute: nil
      )
    )
    return registry
  }

  private func event(from part: TextStreamPart, file: StaticString, line: UInt) -> Event? {
    switch part {
    case .textStart(let id, _):
      return .textStart(id)
    case .textDelta(let id, let text, _):
      return .textDelta(id, text)
    case .textEnd(let id, _):
      return .textEnd(id)
    case .toolCall(let call):
      return .toolCall(.init(call))
    case .toolResult(let result):
      return .toolResult(.init(result))
    case .toolApprovalRequest(let request):
      return .toolApprovalRequest(.init(request))
    case .finish(let finishReason, let rawFinishReason, let totalUsage):
      return .finish(finishReason, totalUsage, rawFinishReason)
    case .error(let message):
      return .error(message)
    default:
      XCTFail("Unhandled stream part: \(part)", file: file, line: line)
      return nil
    }
  }

  private func collectEvents(
    _ stream: AsyncThrowingStream<TextStreamPart, Error>,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws -> [Event] {
    var events: [Event] = []
    for try await part in stream {
      if let event = event(from: part, file: file, line: line) {
        events.append(event)
      }
    }
    return events
  }

  func testForwardTextParts() async throws {
    let stream = makeStream([
      .textStart(id: "1"),
      .textDelta(id: "1", text: "text"),
      .textEnd(id: "1"),
      .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
    ])

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: nil,
        messages: [],
        system: nil,
        repairToolCall: nil,
        experimentalContext: nil
      )
    )

    let result = try await collectEvents(transformed)

    let expected: [Event] = [
      .textStart("1"),
      .textDelta("1", "text"),
      .textEnd("1"),
      .finish(.stop, usage, nil),
    ]
    XCTAssertEqual(result, expected)
  }

  func testHandleAsyncToolExecution() async throws {
    let stream = makeStream([
      .toolCall(
        .init(
          toolCallID: "call-1",
          toolName: "syncTool",
          inputJSON: "{ \"value\": \"test\" }"
        )
      ),
      .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
    ])

    let tools = registryForTool(
      name: "syncTool",
      title: "Sync Tool",
      inputSchema: schemaForValueInput(),
      execute: { input, _ in
        try await Task.sleep(nanoseconds: 1_000_000)
        return .final("\(input.value)-sync-result")
      }
    )

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: tools,
        messages: [],
        system: nil,
        repairToolCall: nil,
        experimentalContext: nil
      )
    )

    let result = try await collectEvents(transformed)

    let expected: [Event] = [
      .toolCall(
        ToolCallSnapshot(
          ToolCall(
            toolCallID: "call-1",
            toolName: "syncTool",
            inputJSON: "{ \"value\": \"test\" }",
            input: .object(["value": .string("test")]),
            providerExecuted: nil,
            dynamic: nil,
            title: "Sync Tool",
            providerMetadata: nil
          )
        )
      ),
      .toolResult(
        ToolResultSnapshot(
          ToolResult(
            toolCallID: "call-1",
            toolName: "syncTool",
            inputJSON: "{ \"value\": \"test\" }",
            input: .object(["value": .string("test")]),
            output: .string("test-sync-result"),
            preliminary: false,
            providerExecuted: nil,
            dynamic: false,
            title: "Sync Tool",
            providerMetadata: nil
          )
        )
      ),
      .finish(.stop, usage, nil),
    ]
    XCTAssertEqual(result, expected)
  }

  func testHandleSyncToolExecution() async throws {
    let stream = makeStream([
      .toolCall(
        .init(
          toolCallID: "call-1",
          toolName: "syncTool",
          inputJSON: "{ \"value\": \"test\" }"
        )
      ),
      .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
    ])

    let tools = registryForTool(
      name: "syncTool",
      title: "Sync Tool",
      inputSchema: schemaForValueInput(),
      execute: { input, _ in
        return .final("\(input.value)-sync-result")
      }
    )

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: tools,
        messages: [],
        system: nil,
        repairToolCall: nil,
        experimentalContext: nil
      )
    )

    let result = try await collectEvents(transformed)

    let expected: [Event] = [
      .toolCall(
        ToolCallSnapshot(
          ToolCall(
            toolCallID: "call-1",
            toolName: "syncTool",
            inputJSON: "{ \"value\": \"test\" }",
            input: .object(["value": .string("test")]),
            providerExecuted: nil,
            dynamic: nil,
            title: "Sync Tool",
            providerMetadata: nil
          )
        )
      ),
      .toolResult(
        ToolResultSnapshot(
          ToolResult(
            toolCallID: "call-1",
            toolName: "syncTool",
            inputJSON: "{ \"value\": \"test\" }",
            input: .object(["value": .string("test")]),
            output: .string("test-sync-result"),
            preliminary: false,
            providerExecuted: nil,
            dynamic: false,
            title: "Sync Tool",
            providerMetadata: nil
          )
        )
      ),
      .finish(.stop, usage, nil),
    ]
    XCTAssertEqual(result, expected)
  }

  func testDelayedToolResultFinishesAfterExecution() async throws {
    let stream = makeStream([
      .toolCall(
        .init(
          toolCallID: "call-1",
          toolName: "delayedTool",
          inputJSON: "{ \"value\": \"test\" }"
        )
      ),
      .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
    ])

    let tools = registryForTool(
      name: "delayedTool",
      title: "Delayed Tool",
      inputSchema: schemaForValueInput(),
      execute: { input, _ in
        try await Task.sleep(nanoseconds: 2_000_000)
        return .final("\(input.value)-delayed-result")
      }
    )

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: tools,
        messages: [],
        system: nil,
        repairToolCall: nil,
        experimentalContext: nil
      )
    )

    let result = try await collectEvents(transformed)

    let expected: [Event] = [
      .toolCall(
        ToolCallSnapshot(
          ToolCall(
            toolCallID: "call-1",
            toolName: "delayedTool",
            inputJSON: "{ \"value\": \"test\" }",
            input: .object(["value": .string("test")]),
            providerExecuted: nil,
            dynamic: nil,
            title: "Delayed Tool",
            providerMetadata: nil
          )
        )
      ),
      .toolResult(
        ToolResultSnapshot(
          ToolResult(
            toolCallID: "call-1",
            toolName: "delayedTool",
            inputJSON: "{ \"value\": \"test\" }",
            input: .object(["value": .string("test")]),
            output: .string("test-delayed-result"),
            preliminary: false,
            providerExecuted: nil,
            dynamic: false,
            title: "Delayed Tool",
            providerMetadata: nil
          )
        )
      ),
      .finish(.stop, usage, nil),
    ]
    XCTAssertEqual(result, expected)
  }

  func testRepairToolCallWhenToolNameNotFound() async throws {
    let stream = makeStream([
      .toolCall(
        .init(
          toolCallID: "call-1",
          toolName: "unknownTool",
          inputJSON: "{ \"value\": \"test\" }"
        )
      ),
      .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
    ])

    let tools = registryForTool(
      name: "correctTool",
      inputSchema: schemaForValueInput(),
      execute: { input, _ in
        return .final("\(input.value)-result")
      }
    )

    let repairToolCall: ToolCallRepairFunction = { context in
      switch context.error {
      case .noSuchTool(let toolName):
        XCTAssertEqual(toolName, "unknownTool")
      default:
        XCTFail("Expected noSuchTool repair error")
      }
      XCTAssertEqual(context.toolCall.toolName, "unknownTool")
      return ToolCall(
        toolCallID: context.toolCall.toolCallID,
        toolName: "correctTool",
        inputJSON: context.toolCall.inputJSON
      )
    }

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: tools,
        messages: [],
        system: nil,
        repairToolCall: repairToolCall,
        experimentalContext: nil
      )
    )

    let result = try await collectEvents(transformed)

    let expected: [Event] = [
      .toolCall(
        ToolCallSnapshot(
          ToolCall(
            toolCallID: "call-1",
            toolName: "correctTool",
            inputJSON: "{ \"value\": \"test\" }",
            input: .object(["value": .string("test")]),
            providerExecuted: nil,
            dynamic: nil,
            title: nil,
            providerMetadata: nil
          )
        )
      ),
      .toolResult(
        ToolResultSnapshot(
          ToolResult(
            toolCallID: "call-1",
            toolName: "correctTool",
            inputJSON: "{ \"value\": \"test\" }",
            input: .object(["value": .string("test")]),
            output: .string("test-result"),
            preliminary: false,
            providerExecuted: nil,
            dynamic: false,
            title: nil,
            providerMetadata: nil
          )
        )
      ),
      .finish(.stop, usage, nil),
    ]
    XCTAssertEqual(result, expected)
  }

  func testProviderExecutedToolDoesNotExecute() async throws {
    let toolExecuted = FlagBox()

    let stream = makeStream([
      .toolCall(
        .init(
          toolCallID: "call-1",
          toolName: "providerTool",
          inputJSON: "{ \"value\": \"test\" }",
          providerExecuted: true
        )
      ),
      .toolResult(
        .init(
          toolCallID: "call-1",
          toolName: "providerTool",
          output: .object(["example": .string("example")]),
          providerExecuted: true
        )
      ),
      .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
    ])

    let tools = registryForTool(
      name: "providerTool",
      inputSchema: schemaForValueInput(),
      execute: { input, _ in
        toolExecuted.set(true)
        return .final("\(input.value)-should-not-execute")
      }
    )

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: tools,
        messages: [],
        system: nil,
        repairToolCall: nil,
        experimentalContext: nil
      )
    )

    _ = try await collectEvents(transformed)

    XCTAssertEqual(toolExecuted.get(), false)
  }

  func testProviderEmittedApprovalRequestIncludesToolCall() async throws {
    let stream = makeStream([
      .toolCall(
        .init(
          toolCallID: "mcp-call-1",
          toolName: "mcp_tool",
          inputJSON: "{ \"query\": \"test\" }",
          providerExecuted: true
        )
      ),
      .toolApprovalRequest(.init(approvalID: "mcp-approval-1", toolCallID: "mcp-call-1")),
      .finish(finishReason: .toolCalls, usage: usage, providerMetadata: nil),
    ])

    let tools = registryForTool(
      name: "mcp_tool",
      inputSchema: schemaForQueryInput()
    )

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: tools,
        messages: [],
        system: nil,
        repairToolCall: nil,
        experimentalContext: nil
      )
    )

    let result = try await collectEvents(transformed)

    let expected: [Event] = [
      .toolCall(
        ToolCallSnapshot(
          ToolCall(
            toolCallID: "mcp-call-1",
            toolName: "mcp_tool",
            inputJSON: "{ \"query\": \"test\" }",
            input: .object(["query": .string("test")]),
            providerExecuted: true,
            dynamic: nil,
            title: nil,
            providerMetadata: nil
          )
        )
      ),
      .toolApprovalRequest(
        ToolApprovalRequestSnapshot(
          ToolApprovalRequest(
            approvalID: "mcp-approval-1",
            toolCallID: "mcp-call-1",
            toolCall: ToolCall(
              toolCallID: "mcp-call-1",
              toolName: "mcp_tool",
              inputJSON: "{ \"query\": \"test\" }",
              input: .object(["query": .string("test")]),
              providerExecuted: true,
              dynamic: nil,
              title: nil,
              providerMetadata: nil
            )
          )
        )
      ),
      .finish(.toolCalls, usage, nil),
    ]
    XCTAssertEqual(result, expected)
  }

  func testProviderApprovalRequestWithoutToolCallEmitsError() async throws {
    let stream = makeStream([
      .toolApprovalRequest(.init(approvalID: "mcp-approval-1", toolCallID: "missing-call")),
      .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
    ])

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: nil,
        messages: [],
        system: nil,
        repairToolCall: nil,
        experimentalContext: nil
      )
    )

    let result = try await collectEvents(transformed)

    let expected: [Event] = [
      .error("Tool call \"missing-call\" not found for approval request \"mcp-approval-1\"."),
      .finish(.stop, usage, nil),
    ]
    XCTAssertEqual(result, expected)
  }

  func testMultipleProviderApprovalRequests() async throws {
    let stream = makeStream([
      .toolCall(
        .init(
          toolCallID: "mcp-call-1",
          toolName: "mcp_search",
          inputJSON: "{ \"query\": \"first\" }",
          providerExecuted: true
        )
      ),
      .toolCall(
        .init(
          toolCallID: "mcp-call-2",
          toolName: "mcp_execute",
          inputJSON: "{ \"command\": \"ls\" }",
          providerExecuted: true
        )
      ),
      .toolApprovalRequest(.init(approvalID: "approval-1", toolCallID: "mcp-call-1")),
      .toolApprovalRequest(.init(approvalID: "approval-2", toolCallID: "mcp-call-2")),
      .finish(finishReason: .toolCalls, usage: usage, providerMetadata: nil),
    ])

    var tools = ToolRegistry()
    tools.register(
      ToolID<QueryInput, String>("mcp_search"),
      ToolSpec(
        inputSchema: schemaForQueryInput()
      )
    )
    tools.register(
      ToolID<CommandInput, String>("mcp_execute"),
      ToolSpec(
        inputSchema: schemaForCommandInput()
      )
    )

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: tools,
        messages: [],
        system: nil,
        repairToolCall: nil,
        experimentalContext: nil
      )
    )

    let result = try await collectEvents(transformed)

    let expected: [Event] = [
      .toolCall(
        ToolCallSnapshot(
          ToolCall(
            toolCallID: "mcp-call-1",
            toolName: "mcp_search",
            inputJSON: "{ \"query\": \"first\" }",
            input: .object(["query": .string("first")]),
            providerExecuted: true,
            dynamic: nil,
            title: nil,
            providerMetadata: nil
          )
        )
      ),
      .toolCall(
        ToolCallSnapshot(
          ToolCall(
            toolCallID: "mcp-call-2",
            toolName: "mcp_execute",
            inputJSON: "{ \"command\": \"ls\" }",
            input: .object(["command": .string("ls")]),
            providerExecuted: true,
            dynamic: nil,
            title: nil,
            providerMetadata: nil
          )
        )
      ),
      .toolApprovalRequest(
        ToolApprovalRequestSnapshot(
          ToolApprovalRequest(
            approvalID: "approval-1",
            toolCallID: "mcp-call-1",
            toolCall: ToolCall(
              toolCallID: "mcp-call-1",
              toolName: "mcp_search",
              inputJSON: "{ \"query\": \"first\" }",
              input: .object(["query": .string("first")]),
              providerExecuted: true,
              dynamic: nil,
              title: nil,
              providerMetadata: nil
            )
          )
        )
      ),
      .toolApprovalRequest(
        ToolApprovalRequestSnapshot(
          ToolApprovalRequest(
            approvalID: "approval-2",
            toolCallID: "mcp-call-2",
            toolCall: ToolCall(
              toolCallID: "mcp-call-2",
              toolName: "mcp_execute",
              inputJSON: "{ \"command\": \"ls\" }",
              input: .object(["command": .string("ls")]),
              providerExecuted: true,
              dynamic: nil,
              title: nil,
              providerMetadata: nil
            )
          )
        )
      ),
      .finish(.toolCalls, usage, nil),
    ]
    XCTAssertEqual(result, expected)
  }

  func testOnInputAvailableBeforeToolCall() async throws {
    let recorder = EventRecorder()
    let stream = makeStream([
      .toolCall(
        .init(
          toolCallID: "call-1",
          toolName: "onInputAvailableTool",
          inputJSON: "{ \"value\": \"test\" }"
        )
      ),
      .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
    ])

    let tools = registryForTool(
      name: "onInputAvailableTool",
      inputSchema: schemaForValueInput(),
      onInputAvailable: { input, _ in
        await recorder.append(.onInputAvailable(.object(["value": .string(input.value)])))
      }
    )

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: tools,
        messages: [],
        system: nil,
        repairToolCall: nil,
        experimentalContext: nil
      )
    )

    for try await part in transformed {
      if let event = event(from: part, file: #filePath, line: #line) {
        await recorder.append(event)
      }
    }

    let result = await recorder.snapshot()

    let expected: [Event] = [
      .onInputAvailable(.object(["value": .string("test")])),
      .toolCall(
        ToolCallSnapshot(
          ToolCall(
            toolCallID: "call-1",
            toolName: "onInputAvailableTool",
            inputJSON: "{ \"value\": \"test\" }",
            input: .object(["value": .string("test")]),
            providerExecuted: nil,
            dynamic: nil,
            title: nil,
            providerMetadata: nil
          )
        )
      ),
      .finish(.stop, usage, nil),
    ]
    XCTAssertEqual(result, expected)
  }

  func testOnInputAvailableWhenApprovalRequired() async throws {
    let recorder = EventRecorder()
    let stream = makeStream([
      .toolCall(
        .init(
          toolCallID: "call-1",
          toolName: "onInputAvailableTool",
          inputJSON: "{ \"value\": \"test\" }"
        )
      ),
      .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
    ])

    let tools = registryForTool(
      name: "onInputAvailableTool",
      inputSchema: schemaForValueInput(),
      needsApproval: { _, _ in true },
      onInputAvailable: { input, _ in
        await recorder.append(.onInputAvailable(.object(["value": .string(input.value)])))
      }
    )

    let idGenerator = IDGeneratorBox(prefix: "id")
    let transformed = runToolsTransformation(
      .init(
        generateID: { idGenerator.generate() },
        generatorStream: stream,
        tools: tools,
        messages: [],
        system: nil,
        repairToolCall: nil,
        experimentalContext: nil
      )
    )

    for try await part in transformed {
      if let event = event(from: part, file: #filePath, line: #line) {
        await recorder.append(event)
      }
    }

    let result = await recorder.snapshot()

    let expected: [Event] = [
      .onInputAvailable(.object(["value": .string("test")])),
      .toolCall(
        ToolCallSnapshot(
          ToolCall(
            toolCallID: "call-1",
            toolName: "onInputAvailableTool",
            inputJSON: "{ \"value\": \"test\" }",
            input: .object(["value": .string("test")]),
            providerExecuted: nil,
            dynamic: nil,
            title: nil,
            providerMetadata: nil
          )
        )
      ),
      .toolApprovalRequest(
        ToolApprovalRequestSnapshot(
          ToolApprovalRequest(
            approvalID: "id-0",
            toolCallID: "call-1",
            toolCall: ToolCall(
              toolCallID: "call-1",
              toolName: "onInputAvailableTool",
              inputJSON: "{ \"value\": \"test\" }",
              input: .object(["value": .string("test")]),
              providerExecuted: nil,
              dynamic: nil,
              title: nil,
              providerMetadata: nil
            )
          )
        )
      ),
      .finish(.stop, usage, nil),
    ]
    XCTAssertEqual(result, expected)
  }
}
