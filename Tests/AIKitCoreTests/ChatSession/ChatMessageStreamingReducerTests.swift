import XCTest
@testable @_spi(Advanced) import AIKitCore
import AIKitProviders

final class ChatMessageStreamingReducerTests: XCTestCase {
  func testTextParts_matchesAISDKTextStateMachine_andBuffersStepStartUntilFirstContent() {
    // Mirrors AI SDK `describe('text', ...)` in:
    // `ai-sdk/packages/ai/src/ui/process-ui-message-stream.test.ts`
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(messageID: "msg-123", messageMetadata: nil),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(messages[0].id, "msg-123")
    XCTAssertEqual(messages[0].role, .assistant)
    XCTAssertEqual(messages[0].parts, [])

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "local-id" })
    XCTAssertEqual(messages[0].parts, [])

    ChatMessageStreamingReducer.apply(.textStart(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    XCTAssertEqual(messages[0].parts.count, 2)
    XCTAssertEqual(messages[0].parts[0], .stepStart)
    guard case let .text(t0) = messages[0].parts[1] else { return XCTFail("expected text part") }
    XCTAssertEqual(t0.id, "text-1")
    XCTAssertEqual(t0.state, .streaming)
    XCTAssertEqual(t0.text, "")

    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "Hello, ", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    guard case let .text(t1) = messages[0].parts[1] else { return XCTFail("expected text part") }
    XCTAssertEqual(t1.text, "Hello, ")

    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "world!", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    guard case let .text(t2) = messages[0].parts[1] else { return XCTFail("expected text part") }
    XCTAssertEqual(t2.text, "Hello, world!")

    ChatMessageStreamingReducer.apply(.textEnd(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    guard case let .text(t3) = messages[0].parts[1] else { return XCTFail("expected text part") }
    XCTAssertEqual(t3.state, .done)
    XCTAssertEqual(t3.text, "Hello, world!")
  }

  func testToolApprovalRequest_staticTool_matchesAISDK() {
    // Mirrors AI SDK `describe('tool approval requests (static tool)', ...)` in:
    // `ai-sdk/packages/ai/src/ui/process-ui-message-stream.test.ts`
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.start(), messages: &messages, state: &state, makeMessageID: { "msg-123" })
    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "msg-123" })

    ChatMessageStreamingReducer.apply(
      .toolInputAvailable(.init(toolCallID: "call-1", toolName: "tool1", input: .object(["value": .string("value")]))),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    ChatMessageStreamingReducer.apply(
      .toolApprovalRequest(approvalID: "id-1", toolCallID: "call-1"),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    XCTAssertEqual(assistant.id, "msg-123")

    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).last else { return XCTFail("missing tool part") }

    XCTAssertEqual(tool.dynamic, false)
    XCTAssertEqual(tool.toolName, "tool1")
    XCTAssertEqual(tool.input, .object(["value": .string("value")]))
    XCTAssertEqual(tool.approval, .init(id: "id-1"))
    XCTAssertEqual(tool.state, .approvalRequested(approvalID: "id-1"))
  }

  func testToolExecutionDenial_staticTool_matchesAISDK_andPreservesApproval() {
    // Mirrors AI SDK `describe('tool execution denial (static tool)', ...)` in:
    // `ai-sdk/packages/ai/src/ui/process-ui-message-stream.test.ts`
    var messages: [ChatMessage] = [
      .init(id: "original-id", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "tool1",
          input: .object(["value": .string("value")]),
          approval: .init(id: "id-1", approved: false),
          state: .approvalResponded(approvalID: "id-1", approved: false, reason: nil)
        )),
      ]),
    ]
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.start(), messages: &messages, state: &state, makeMessageID: { "ignored" })
    ChatMessageStreamingReducer.apply(.toolOutputDenied(toolCallID: "call-1"), messages: &messages, state: &state, makeMessageID: { "ignored" })

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "ignored" })
    ChatMessageStreamingReducer.apply(.textStart(id: "1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "ignored" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "1", delta: "I did not execute the tool.", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "ignored" })
    ChatMessageStreamingReducer.apply(.textEnd(id: "1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "ignored" })

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    XCTAssertEqual(assistant.id, "original-id")
    XCTAssertEqual(assistant.parts.filter { $0 == .stepStart }.count, 2)

    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).first else { return XCTFail("missing tool part") }

    XCTAssertEqual(tool.dynamic, false)
    XCTAssertEqual(tool.approval, .init(id: "id-1", approved: false, reason: nil))
    XCTAssertEqual(tool.state, .outputDenied(approvalID: "id-1", reason: nil))
  }

  func testMessageMetadata_mergesFromStartMessageMetadataAndFinish_withDeepObjectMerge() {
    // Mirrors AI SDK `describe('message metadata', ...)` in:
    // `ai-sdk/packages/ai/src/ui/process-ui-message-stream.test.ts`
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(
        messageID: "msg-123",
        messageMetadata: .object([
          "start": .string("start-1"),
          "shared": .object([
            "key1": .string("value-1a"),
            "key2": .string("value-2a"),
          ]),
        ])
      ),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textStart(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "t1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(
      .messageMetadata(.object([
        "metadata": .string("metadata-1"),
      ])),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "t2", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textEnd(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.finishStep, messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(
      .finish(
        finishReason: nil,
        messageMetadata: .object([
          "finish": .string("finish-1"),
          "shared": .object([
            "key1": .string("value-1e"),
            "key6": .string("value-6e"),
          ]),
        ])
      ),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    XCTAssertEqual(assistant.id, "msg-123")
    XCTAssertEqual(assistant.metadata, .object([
      "start": .string("start-1"),
      "metadata": .string("metadata-1"),
      "finish": .string("finish-1"),
      "shared": .object([
        "key1": .string("value-1e"),
        "key2": .string("value-2a"),
        "key6": .string("value-6e"),
      ]),
    ]))
  }

  func testMessageMetadata_delayedAfterFinish_isStillMerged() {
    // Mirrors AI SDK `describe('message metadata delayed after finish', ...)`.
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(messageID: "msg-123", messageMetadata: nil),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )
    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textStart(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "t1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textEnd(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.finishStep, messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.finish(finishReason: nil, messageMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(
      .messageMetadata(.object(["key1": .string("value-1")])),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    XCTAssertEqual(assistant.id, "msg-123")
    XCTAssertEqual(assistant.metadata, .object(["key1": .string("value-1")]))
  }

  func testMessageMetadata_withExistingAssistantLastMessage_overridesID_andMergesMetadata() {
    // Mirrors AI SDK `describe('message metadata with existing assistant lastMessage', ...)`.
    var messages: [ChatMessage] = [
      .init(
        id: "original-id",
        role: .assistant,
        parts: [],
        metadata: .object([
          "key1": .string("value-1a"),
          "key3": .string("value-3a"),
        ])
      ),
    ]
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(
        messageID: "msg-123",
        messageMetadata: .object([
          "key1": .string("value-1b"),
          "key2": .string("value-2b"),
        ])
      ),
      messages: &messages,
      state: &state,
      makeMessageID: { "ignored" }
    )

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "ignored" })
    ChatMessageStreamingReducer.apply(.textStart(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "ignored" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "t1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "ignored" })
    ChatMessageStreamingReducer.apply(.textEnd(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "ignored" })
    ChatMessageStreamingReducer.apply(.finishStep, messages: &messages, state: &state, makeMessageID: { "ignored" })
    ChatMessageStreamingReducer.apply(.finish(finishReason: nil, messageMetadata: nil), messages: &messages, state: &state, makeMessageID: { "ignored" })

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    XCTAssertEqual(assistant.id, "msg-123")
    XCTAssertEqual(assistant.metadata, .object([
      "key1": .string("value-1b"),
      "key2": .string("value-2b"),
      "key3": .string("value-3a"),
    ]))
  }

  func testDataUIParts_singlePart_matchesAISDK() {
    // Mirrors AI SDK `describe('data ui parts (single part)', ...)` in:
    // `ai-sdk/packages/ai/src/ui/process-ui-message-stream.test.ts`
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(messageID: "msg-123", messageMetadata: nil),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )
    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(
      .data(.init(type: "data-test", data: .string("example-data-can-be-anything"))),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    XCTAssertEqual(assistant.id, "msg-123")
    XCTAssertEqual(assistant.parts, [
      .stepStart,
      .data(.init(type: "data-test", data: .string("example-data-can-be-anything"))),
    ])
  }

  func testDataUIParts_transientPart_isNotAddedToMessageParts_butStepStartStillExists() {
    // Mirrors AI SDK `describe('data ui parts (transient part)', ...)`.
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(messageID: "msg-123", messageMetadata: nil),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )
    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(
      .data(.init(type: "data-test", data: .string("example-data-can-be-anything"), transient: true)),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(messages[0].parts, [])

    ChatMessageStreamingReducer.apply(.finishStep, messages: &messages, state: &state, makeMessageID: { "local-id" })
    XCTAssertEqual(messages[0].parts, [.stepStart])
  }

  func testDataUIParts_singlePartWithID_replacesExistingDataOnUpdate() {
    // Mirrors AI SDK `describe('data ui parts (single part with id and replacement update)', ...)`.
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(messageID: "msg-123", messageMetadata: nil),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )
    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(
      .data(.init(type: "data-test", id: "data-part-id", data: .string("example-data-can-be-anything"))),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    ChatMessageStreamingReducer.apply(
      .data(.init(type: "data-test", id: "data-part-id", data: .string("or-something-else"))),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(messages[0].parts, [
      .stepStart,
      .data(.init(type: "data-test", id: "data-part-id", data: .string("or-something-else"))),
    ])
  }

  func testDataUIParts_singlePartWithID_objectData_replacesEntireObject() {
    // Mirrors AI SDK `describe('data ui parts (single part with id and merge update)', ...)` (replacement semantics).
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(messageID: "msg-123", messageMetadata: nil),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )
    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(
      .data(.init(type: "data-test", id: "data-part-id", data: .object([
        "a": .string("a1"),
        "b": .string("b1"),
      ]))),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    ChatMessageStreamingReducer.apply(
      .data(.init(type: "data-test", id: "data-part-id", data: .object([
        "b": .string("b2"),
        "c": .string("c2"),
      ]))),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(messages[0].parts, [
      .stepStart,
      .data(.init(type: "data-test", id: "data-part-id", data: .object([
        "b": .string("b2"),
        "c": .string("c2"),
      ]))),
    ])
  }

  func testSources_sourceURLPart_matchesAISDK() {
    // Mirrors AI SDK `describe('sources', ...)` in:
    // `ai-sdk/packages/ai/src/ui/process-ui-message-stream.test.ts`
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(messageID: "msg-123", messageMetadata: nil),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textStart(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "The weather in London is sunny.", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textEnd(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(
      .sourceURL(.init(sourceID: "source-id", url: "https://example.com", title: "Example")),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    XCTAssertEqual(assistant.id, "msg-123")
    XCTAssertEqual(assistant.parts, [
      .stepStart,
      .text(.init(id: "text-1", text: "The weather in London is sunny.", state: .done)),
      .sourceURL(.init(sourceID: "source-id", url: "https://example.com", title: "Example")),
    ])
  }

  func testFileParts_multipleFiles_matchesAISDK() {
    // Mirrors AI SDK `describe('file parts', ...)` in:
    // `ai-sdk/packages/ai/src/ui/process-ui-message-stream.test.ts`
    let file1 = URL(string: "data:text/plain;base64,SGVsbG8gV29ybGQ=")!
    let file2 = URL(string: "data:application/json;base64,eyJrZXkiOiJ2YWx1ZSJ9")!

    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(messageID: "msg-123", messageMetadata: nil),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textStart(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "Here is a file:", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textEnd(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(.file(.init(url: file1.absoluteString, mediaType: "text/plain")), messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(.textStart(id: "text-2", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "text-2", delta: "And another one:", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })
    ChatMessageStreamingReducer.apply(.textEnd(id: "text-2", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(.file(.init(url: file2.absoluteString, mediaType: "application/json")), messages: &messages, state: &state, makeMessageID: { "local-id" })

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    XCTAssertEqual(assistant.id, "msg-123")
    XCTAssertEqual(assistant.parts, [
      .stepStart,
      .text(.init(id: "text-1", text: "Here is a file:", state: .done)),
      .file(.init(data: .url(file1), filename: nil, mediaType: "text/plain")),
      .text(.init(id: "text-2", text: "And another one:", state: .done)),
      .file(.init(data: .url(file2), filename: nil, mediaType: "application/json")),
    ])
  }

  func testStartStep_isBufferedUntilFirstContentPart() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "a1" })
    XCTAssertEqual(messages, [])

    ChatMessageStreamingReducer.apply(.textStart(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "a1" })

    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(messages[0].role, .assistant)
    XCTAssertEqual(messages[0].parts.count, 2)
    XCTAssertEqual(messages[0].parts[0], .stepStart)
    guard case let .text(textPart) = messages[0].parts[1] else { return XCTFail("expected text part") }
    XCTAssertEqual(textPart.id, "text-1")
    XCTAssertEqual(textPart.text, "")
    XCTAssertEqual(textPart.state, .streaming)
  }

  func testTextParts_streamStartDeltaEndAccumulateInLastAssistantMessage() {
    var messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [.text(.init(id: "t0", text: "hi", state: .done))]),
    ]
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.textStart(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "a1" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "Hello", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "a1" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: ", world", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "a1" })
    ChatMessageStreamingReducer.apply(.textEnd(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "a1" })

    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages.last?.role, .assistant)

    guard let last = messages.last else { return XCTFail("missing assistant message") }
    guard case let .text(text)? = last.parts.last else { return XCTFail("missing text part") }
    XCTAssertEqual(text.id, "text-1")
    XCTAssertEqual(text.text, "Hello, world")
    XCTAssertEqual(text.state, .done)
  }

  func testReasoningParts_streamStartDeltaEndAccumulateAndPreserveProviderMetadataAcrossMultipleParts() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "msg-123" })

    ChatMessageStreamingReducer.apply(.reasoningStart(id: "reasoning-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })
    ChatMessageStreamingReducer.apply(.reasoningDelta(id: "reasoning-1", delta: "I will open the conversation", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })

    let metadata1: ProviderMetadata = ["testProvider": .object(["signature": .string("1234567890")])]
    ChatMessageStreamingReducer.apply(.reasoningDelta(id: "reasoning-1", delta: " with witty banter. ", providerMetadata: metadata1), messages: &messages, state: &state, makeMessageID: { "msg-123" })
    ChatMessageStreamingReducer.apply(.reasoningEnd(id: "reasoning-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })

    ChatMessageStreamingReducer.apply(.reasoningStart(id: "reasoning-2", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })
    let metadata2: ProviderMetadata = ["testProvider": .object(["isRedacted": .bool(true)])]
    ChatMessageStreamingReducer.apply(.reasoningDelta(id: "reasoning-2", delta: "redacted-data", providerMetadata: metadata2), messages: &messages, state: &state, makeMessageID: { "msg-123" })
    ChatMessageStreamingReducer.apply(.reasoningEnd(id: "reasoning-2", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })

    ChatMessageStreamingReducer.apply(.reasoningStart(id: "reasoning-3", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })
    ChatMessageStreamingReducer.apply(.reasoningDelta(id: "reasoning-3", delta: "Once the user has relaxed,", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })
    let metadata3: ProviderMetadata = ["testProvider": .object(["signature": .string("abc123")])]
    ChatMessageStreamingReducer.apply(.reasoningDelta(id: "reasoning-3", delta: " I will pry for valuable information.", providerMetadata: metadata3), messages: &messages, state: &state, makeMessageID: { "msg-123" })
    ChatMessageStreamingReducer.apply(.reasoningEnd(id: "reasoning-3", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })

    ChatMessageStreamingReducer.apply(.textStart(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "Hi there!", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })
    ChatMessageStreamingReducer.apply(.textEnd(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "msg-123" })

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    XCTAssertEqual(assistant.id, "msg-123")
    XCTAssertEqual(assistant.role, .assistant)
    XCTAssertEqual(assistant.parts.count, 5)

    XCTAssertEqual(assistant.parts[0], .stepStart)

    guard case let .reasoning(r1) = assistant.parts[1] else { return XCTFail("expected reasoning-1 part") }
    XCTAssertEqual(r1.id, "reasoning-1")
    XCTAssertEqual(r1.state, .done)
    XCTAssertEqual(r1.text, "I will open the conversation with witty banter. ")
    XCTAssertEqual(r1.providerMetadata, metadata1)

    guard case let .reasoning(r2) = assistant.parts[2] else { return XCTFail("expected reasoning-2 part") }
    XCTAssertEqual(r2.id, "reasoning-2")
    XCTAssertEqual(r2.state, .done)
    XCTAssertEqual(r2.text, "redacted-data")
    XCTAssertEqual(r2.providerMetadata, metadata2)

    guard case let .reasoning(r3) = assistant.parts[3] else { return XCTFail("expected reasoning-3 part") }
    XCTAssertEqual(r3.id, "reasoning-3")
    XCTAssertEqual(r3.state, .done)
    XCTAssertEqual(r3.text, "Once the user has relaxed, I will pry for valuable information.")
    XCTAssertEqual(r3.providerMetadata, metadata3)

    guard case let .text(t1) = assistant.parts[4] else { return XCTFail("expected text part") }
    XCTAssertEqual(t1.id, "text-1")
    XCTAssertEqual(t1.state, .done)
    XCTAssertEqual(t1.text, "Hi there!")
  }

  func testToolCallAndResult_updateToolPartState() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    let call = ToolInputAvailable(toolCallID: "tool-1", toolName: "getLocation", input: .object([:]))
    ChatMessageStreamingReducer.apply(.toolInputAvailable(call), messages: &messages, state: &state, makeMessageID: { "a1" })

    let result = ToolOutputAvailable(toolCallID: "tool-1", output: .string("NYC"), preliminary: false)
    ChatMessageStreamingReducer.apply(.toolOutputAvailable(result), messages: &messages, state: &state, makeMessageID: { "a1" })

    guard let last = messages.last else { return XCTFail("missing assistant message") }
    guard let toolPart = last.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).first else { return XCTFail("missing tool part") }

    XCTAssertEqual(toolPart.toolCallID, "tool-1")
    XCTAssertEqual(toolPart.toolName, "getLocation")
    XCTAssertEqual(toolPart.output, .string("NYC"))
    if case let .outputAvailable(preliminary) = toolPart.state {
      XCTAssertEqual(preliminary, false)
    } else {
      XCTFail("expected outputAvailable state")
    }
  }

  func testApprovalRequest_createsApprovalRequestedState() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()
    let call = ToolInputAvailable(toolCallID: "tool-1", toolName: "getWeather", input: .object(["city": .string("SF")]))
    ChatMessageStreamingReducer.apply(.toolInputAvailable(call), messages: &messages, state: &state, makeMessageID: { "a1" })

    ChatMessageStreamingReducer.apply(
      .toolApprovalRequest(approvalID: "approval-1", toolCallID: "tool-1"),
      messages: &messages,
      state: &state,
      makeMessageID: { "a1" }
    )

    guard let last = messages.last else { return XCTFail("missing assistant message") }
    guard let toolPart = last.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).first else { return XCTFail("missing tool part") }

    if case let .approvalRequested(approvalID) = toolPart.state {
      XCTAssertEqual(approvalID, "approval-1")
    } else {
      XCTFail("expected approvalRequested state")
    }
  }

  func testToolInputStreaming_matchesAISDKToolCallStreamingStateMachine() {
    // Mirrors AI SDK `describe('tool call streaming', ...)` in:
    // `ai-sdk/packages/ai/src/ui/process-ui-message-stream.test.ts`
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .start(messageID: "msg-123", messageMetadata: nil),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )
    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "local-id" })

    ChatMessageStreamingReducer.apply(
      .toolInputStart(.init(toolCallID: "tool-call-0", toolName: "test-tool")),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    do {
      guard let assistant = messages.last else { return XCTFail("missing assistant message") }
      XCTAssertEqual(assistant.id, "msg-123")
      XCTAssertEqual(assistant.parts, [
        .stepStart,
        .tool(.init(toolCallID: "tool-call-0", toolName: "test-tool", state: .inputStreaming)),
      ])
    }

    ChatMessageStreamingReducer.apply(
      .toolInputDelta(.init(toolCallID: "tool-call-0", inputTextDelta: "{\"testArg\":\"t")),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    do {
      guard let assistant = messages.last else { return XCTFail("missing assistant message") }
      guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }).first else { return XCTFail("missing tool part") }

      XCTAssertEqual(tool.state, .inputStreaming)
      XCTAssertEqual(tool.input, .object(["testArg": .string("t")]))
    }

    ChatMessageStreamingReducer.apply(
      .toolInputDelta(.init(toolCallID: "tool-call-0", inputTextDelta: "est-value\"}}")),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    do {
      guard let assistant = messages.last else { return XCTFail("missing assistant message") }
      guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }).first else { return XCTFail("missing tool part") }

      XCTAssertEqual(tool.state, .inputStreaming)
      XCTAssertEqual(tool.input, .object(["testArg": .string("test-value")]))
    }

    ChatMessageStreamingReducer.apply(
      .toolInputAvailable(.init(toolCallID: "tool-call-0", toolName: "test-tool", input: .object(["testArg": .string("test-value")]))),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    do {
      guard let assistant = messages.last else { return XCTFail("missing assistant message") }
      guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }).first else { return XCTFail("missing tool part") }

      XCTAssertEqual(tool.state, .inputAvailable)
      XCTAssertEqual(tool.input, .object(["testArg": .string("test-value")]))
    }

    ChatMessageStreamingReducer.apply(
      .toolOutputAvailable(.init(toolCallID: "tool-call-0", output: .string("test-result"), preliminary: false)),
      messages: &messages,
      state: &state,
      makeMessageID: { "local-id" }
    )

    do {
      guard let assistant = messages.last else { return XCTFail("missing assistant message") }
      guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }).first else { return XCTFail("missing tool part") }

      XCTAssertEqual(tool.state, .outputAvailable(preliminary: false))
      XCTAssertEqual(tool.input, .object(["testArg": .string("test-value")]))
      XCTAssertEqual(tool.output, .string("test-result"))
    }
  }

  func testToolInputError_setsRawInputAndClearsParsedInput_andToolOutputErrorPreservesRawInput() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "msg-123" })

    ChatMessageStreamingReducer.apply(
      .toolInputStart(.init(toolCallID: "call-1", toolName: "cityAttractions")),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    ChatMessageStreamingReducer.apply(
      .toolInputDelta(.init(toolCallID: "call-1", inputTextDelta: "{ \"cities\": \"San Francisco\" }")),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    do {
      guard let assistant = messages.last else { return XCTFail("missing assistant message") }
      guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }).last else { return XCTFail("missing tool part") }

      XCTAssertEqual(tool.state, .inputStreaming)
      XCTAssertNotNil(tool.input)
    }

    ChatMessageStreamingReducer.apply(
      .toolInputError(.init(
        toolCallID: "call-1",
        toolName: "cityAttractions",
        input: .string("{ \"cities\": \"San Francisco\" }"),
        providerExecuted: nil,
        providerMetadata: nil,
        dynamic: nil,
        errorText: "Invalid input for tool cityAttractions",
        title: nil
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    do {
      guard let assistant = messages.last else { return XCTFail("missing assistant message") }
      guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }).last else { return XCTFail("missing tool part") }

      XCTAssertEqual(tool.state, .outputError(errorText: "Invalid input for tool cityAttractions"))
      XCTAssertNil(tool.input)
      XCTAssertEqual(tool.rawInput, .string("{ \"cities\": \"San Francisco\" }"))
    }

    ChatMessageStreamingReducer.apply(
      .toolOutputError(.init(toolCallID: "call-1", errorText: "Invalid input for tool cityAttractions", providerExecuted: nil, dynamic: nil)),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    do {
      guard let assistant = messages.last else { return XCTFail("missing assistant message") }
      guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }).last else { return XCTFail("missing tool part") }

      XCTAssertEqual(tool.state, .outputError(errorText: "Invalid input for tool cityAttractions"))
      XCTAssertNil(tool.input)
      XCTAssertEqual(tool.rawInput, .string("{ \"cities\": \"San Francisco\" }"))
    }
  }

  func testToolCall_providerMetadata_isStoredOnToolPart() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    let metadata: ProviderMetadata = ["openai": .object(["trace_id": .string("abc")])]
    let call = ToolInputAvailable(
      toolCallID: "tool-1",
      toolName: "getWeather",
      input: .object([:]),
      providerMetadata: metadata
    )

    ChatMessageStreamingReducer.apply(.toolInputAvailable(call), messages: &messages, state: &state, makeMessageID: { "a1" })

    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).first else { return XCTFail("missing tool part") }

    XCTAssertEqual(tool.callProviderMetadata, metadata)
  }

  func testTextDelta_withEmptyTextStillUpdatesProviderMetadata() {
    var messages: [ChatMessage] = [.init(id: "u1", role: .user, parts: [.text(.init(id: "t0", text: "hi", state: .done))])]
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.textStart(id: "text-1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "a1" })

    let metadata: ProviderMetadata = ["openai": .object(["trace_id": .string("t-123")])]
    ChatMessageStreamingReducer.apply(.textDelta(id: "text-1", delta: "", providerMetadata: metadata), messages: &messages, state: &state, makeMessageID: { "a1" })

    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    guard let text = assistant.parts.compactMap({ part -> ChatTextPart? in
      guard case let .text(text) = part else { return nil }
      return text
    }).last else { return XCTFail("missing text part") }

    XCTAssertEqual(text.providerMetadata, metadata)
  }

  func testToolOutputDenied_preservesApprovalIDFromPriorApprovalResponse() {
    var messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "tool1",
          providerExecuted: false,
          dynamic: true,
          input: .object(["value": .string("value")]),
          output: nil,
          callProviderMetadata: nil,
          state: .approvalResponded(approvalID: "approval-1", approved: false, reason: "nope")
        )),
      ]),
    ]
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(
      .toolOutputDenied(toolCallID: "call-1"),
      messages: &messages,
      state: &state,
      makeMessageID: { "a1" }
    )

    guard let assistant = messages.last else { return XCTFail("missing assistant message") }
    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).last else { return XCTFail("missing tool part") }

    XCTAssertEqual(tool.state, .outputDenied(approvalID: "approval-1", reason: "nope"))
  }

  func testPreliminaryToolResults_updateOutputAndPreliminaryFlag_untilFinalOutputAvailable() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "msg-123" })

    ChatMessageStreamingReducer.apply(
      .toolInputAvailable(.init(
        toolCallID: "call-1",
        toolName: "cityAttractions",
        input: .object(["city": .string("San Francisco")])
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    ChatMessageStreamingReducer.apply(
      .toolOutputAvailable(.init(
        toolCallID: "call-1",
        output: .object(["status": .string("loading"), "text": .string("Getting weather for San Francisco")]),
        preliminary: true
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    ChatMessageStreamingReducer.apply(
      .toolOutputAvailable(.init(
        toolCallID: "call-1",
        output: .object([
          "status": .string("success"),
          "temperature": .number(72),
          "text": .string("The weather in San Francisco is 72°F"),
        ]),
        preliminary: true
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    ChatMessageStreamingReducer.apply(
      .toolOutputAvailable(.init(
        toolCallID: "call-1",
        output: .object([
          "status": .string("success"),
          "temperature": .number(72),
          "text": .string("The weather in San Francisco is 72°F"),
        ]),
        preliminary: nil
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant") }
    XCTAssertEqual(assistant.id, "msg-123")
    XCTAssertEqual(assistant.role, .assistant)
    XCTAssertEqual(assistant.parts.first, .stepStart)

    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).first else { return XCTFail("missing tool part") }

    XCTAssertEqual(tool.toolCallID, "call-1")
    XCTAssertEqual(tool.toolName, "cityAttractions")
    XCTAssertEqual(tool.input, .object(["city": .string("San Francisco")]))
    XCTAssertEqual(tool.output, .object([
      "status": .string("success"),
      "temperature": .number(72),
      "text": .string("The weather in San Francisco is 72°F"),
    ]))
    XCTAssertEqual(tool.state, .outputAvailable(preliminary: false))
  }

  func testToolTitleSupport_staticTool_titlePreservedAcrossStates() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "msg-123" })

    ChatMessageStreamingReducer.apply(
      .toolInputStart(.init(
        toolCallID: "tool-call-0",
        toolName: "weatherTool",
        title: "Weather Information"
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    do {
      guard let tool = messages.last?.parts.compactMap({ part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }).last else { return XCTFail("missing tool part") }
      XCTAssertEqual(tool.title, "Weather Information")
      XCTAssertEqual(tool.state, .inputStreaming)
    }

    ChatMessageStreamingReducer.apply(
      .toolInputDelta(.init(
        toolCallID: "tool-call-0",
        inputTextDelta: "{\"location\":\"Paris\"}"
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    ChatMessageStreamingReducer.apply(
      .toolInputAvailable(.init(
        toolCallID: "tool-call-0",
        toolName: "weatherTool",
        input: .object(["location": .string("Paris")]),
        title: "Weather Information"
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    do {
      guard let tool = messages.last?.parts.compactMap({ part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }).last else { return XCTFail("missing tool part") }
      XCTAssertEqual(tool.title, "Weather Information")
      XCTAssertEqual(tool.state, .inputAvailable)
    }

    ChatMessageStreamingReducer.apply(
      .toolOutputAvailable(.init(toolCallID: "tool-call-0", output: .string("Sunny, 22°C"))),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    do {
      guard let tool = messages.last?.parts.compactMap({ part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }).last else { return XCTFail("missing tool part") }
      XCTAssertEqual(tool.title, "Weather Information")
      XCTAssertEqual(tool.state, .outputAvailable(preliminary: false))
      XCTAssertEqual(tool.output, .string("Sunny, 22°C"))
    }
  }

  func testToolTitleSupport_dynamicTool_titlePreservedAcrossStates() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "msg-456" })

    ChatMessageStreamingReducer.apply(
      .toolInputStart(.init(
        toolCallID: "tool-call-1",
        toolName: "calculate",
        dynamic: true,
        title: "Calculator"
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-456" }
    )

    ChatMessageStreamingReducer.apply(
      .toolInputAvailable(.init(
        toolCallID: "tool-call-1",
        toolName: "calculate",
        input: .object(["a": .number(5), "b": .number(3)]),
        dynamic: true,
        title: "Calculator"
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-456" }
    )

    ChatMessageStreamingReducer.apply(
      .toolOutputAvailable(.init(
        toolCallID: "tool-call-1",
        output: .object(["result": .number(8)]),
        dynamic: true
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-456" }
    )

    guard let assistant = messages.last else { return XCTFail("missing assistant") }
    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).last else { return XCTFail("missing tool part") }

    XCTAssertEqual(tool.dynamic, true)
    XCTAssertEqual(tool.toolName, "calculate")
    XCTAssertEqual(tool.title, "Calculator")
    XCTAssertEqual(tool.input, .object(["a": .number(5), "b": .number(3)]))
    XCTAssertEqual(tool.output, .object(["result": .number(8)]))
    XCTAssertEqual(tool.state, .outputAvailable(preliminary: false))
  }

  func testToolTitleSupport_toolOutputError_preservesTitle() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "msg-error" })

    ChatMessageStreamingReducer.apply(
      .toolInputStart(.init(
        toolCallID: "tool-call-error",
        toolName: "errorTool",
        title: "Error Tool"
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-error" }
    )

    ChatMessageStreamingReducer.apply(
      .toolInputAvailable(.init(
        toolCallID: "tool-call-error",
        toolName: "errorTool",
        input: .object(["invalid": .string("data")]),
        title: "Error Tool"
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-error" }
    )

    ChatMessageStreamingReducer.apply(
      .toolOutputError(.init(toolCallID: "tool-call-error", errorText: "Tool execution failed")),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-error" }
    )

    guard let assistant = messages.last else { return XCTFail("missing assistant") }
    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).last else { return XCTFail("missing tool part") }

    XCTAssertEqual(tool.title, "Error Tool")
    XCTAssertEqual(tool.state, .outputError(errorText: "Tool execution failed"))
  }

  func testToolApprovalRequest_dynamicTool_updatesToolStateAndApprovalID() {
    var messages: [ChatMessage] = []
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "msg-123" })

    ChatMessageStreamingReducer.apply(
      .toolInputAvailable(.init(
        toolCallID: "call-1",
        toolName: "tool1",
        input: .object(["value": .string("value")]),
        dynamic: true
      )),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    ChatMessageStreamingReducer.apply(
      .toolApprovalRequest(approvalID: "id-1", toolCallID: "call-1"),
      messages: &messages,
      state: &state,
      makeMessageID: { "msg-123" }
    )

    guard let assistant = messages.last else { return XCTFail("missing assistant") }
    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).last else { return XCTFail("missing tool part") }

    XCTAssertEqual(tool.dynamic, true)
    XCTAssertEqual(tool.approval, .init(id: "id-1"))
    XCTAssertEqual(tool.state, .approvalRequested(approvalID: "id-1"))
  }

  func testToolExecutionDenial_dynamicTool_setsOutputDenied_andSubsequentStepTextAppends() {
    var messages: [ChatMessage] = [
      .init(id: "original-id", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call-1",
          toolName: "tool1",
          dynamic: true,
          input: .object(["value": .string("value")]),
          approval: .init(id: "id-1", approved: false),
          state: .approvalResponded(approvalID: "id-1", approved: false, reason: nil)
        )),
      ]),
    ]
    var state = ChatMessageStreamingReducer.State()

    ChatMessageStreamingReducer.apply(.toolOutputDenied(toolCallID: "call-1"), messages: &messages, state: &state, makeMessageID: { "original-id" })

    ChatMessageStreamingReducer.apply(.startStep, messages: &messages, state: &state, makeMessageID: { "original-id" })
    ChatMessageStreamingReducer.apply(.textStart(id: "1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "original-id" })
    ChatMessageStreamingReducer.apply(.textDelta(id: "1", delta: "I did not execute the tool.", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "original-id" })
    ChatMessageStreamingReducer.apply(.textEnd(id: "1", providerMetadata: nil), messages: &messages, state: &state, makeMessageID: { "original-id" })

    XCTAssertEqual(messages.count, 1)
    guard let assistant = messages.last else { return XCTFail("missing assistant") }
    XCTAssertEqual(assistant.id, "original-id")
    XCTAssertEqual(assistant.parts.filter { $0 == .stepStart }.count, 2)

    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).first else { return XCTFail("missing tool part") }

    XCTAssertEqual(tool.dynamic, true)
    XCTAssertEqual(tool.approval, .init(id: "id-1", approved: false, reason: nil))
    XCTAssertEqual(tool.state, .outputDenied(approvalID: "id-1", reason: nil))

    guard let text = assistant.parts.compactMap({ part -> ChatTextPart? in
      guard case let .text(t) = part else { return nil }
      return t
    }).last else { return XCTFail("missing text part") }

    XCTAssertEqual(text.state, .done)
    XCTAssertEqual(text.text, "I did not execute the tool.")
  }
}
