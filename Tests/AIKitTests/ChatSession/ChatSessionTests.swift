import XCTest
@testable @_spi(Advanced) import AIKit
import AIKitProviders
import AIKitTestKit

final class ChatSessionTests: XCTestCase {
  private final class IDGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var nextValue = 0

    func nextID(prefix: String = "id-") -> String {
      lock.lock()
      defer { lock.unlock() }
      let result = "\(prefix)\(nextValue)"
      nextValue += 1
      return result
    }
  }

  private actor RequestCapture {
    struct Capture: Sendable, Equatable {
      var chatID: String
      var messages: [ChatMessage]
      var trigger: ChatRequestTrigger
      var messageID: String?
      var options: ChatRequestOptions?
    }

    private var value: Capture?

    func record(
      chatID: String,
      messages: [ChatMessage],
      trigger: ChatRequestTrigger,
      messageID: String?,
      options: ChatRequestOptions?
    ) {
      self.value = .init(chatID: chatID, messages: messages, trigger: trigger, messageID: messageID, options: options)
    }

    func snapshot() -> Capture? { value }
  }

  private actor FinishCapture {
    private var value: ChatSessionFinishEvent?
    func set(_ event: ChatSessionFinishEvent) { value = event }
    func snapshot() -> ChatSessionFinishEvent? { value }
  }

  private actor DataCapture {
    private var entries: [AIUIMessageStreamDataPart] = []
    func append(_ part: AIUIMessageStreamDataPart) { entries.append(part) }
    func snapshot() -> [AIUIMessageStreamDataPart] { entries }
  }

  private actor StreamErrorCapture {
    private var errors: [Error] = []
    func append(_ error: Error) { errors.append(error) }
    func snapshot() -> [Error] { errors }
  }

  private struct ValidationError: Error, Equatable {}

  private actor MessageHistory {
    private var entries: [[ChatMessage]] = []
    func append(_ messages: [ChatMessage]) { entries.append(messages) }
    func snapshot() -> [[ChatMessage]] { entries }
  }

  private actor StreamTerminationCapture {
    private var wasCancelled = false
    func markCancelled() { wasCancelled = true }
    func snapshotWasCancelled() -> Bool { wasCancelled }
  }

  private actor StreamQueue {
    var continuations: [AsyncThrowingStream<ModelStreamPart, Error>.Continuation] = []

    func enqueue(_ continuation: AsyncThrowingStream<ModelStreamPart, Error>.Continuation) {
      continuations.append(continuation)
    }

    func continuation(at index: Int) -> AsyncThrowingStream<ModelStreamPart, Error>.Continuation? {
      guard continuations.indices.contains(index) else { return nil }
      return continuations[index]
    }

    func count() -> Int { continuations.count }
  }

  private struct EmptyInput: Codable, Sendable, Equatable {}

  private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollNanoseconds: UInt64 = 2_000_000,
    _ predicate: @escaping @Sendable () async -> Bool
  ) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if await predicate() { return }
      try await Task.sleep(nanoseconds: pollNanoseconds)
    }

    struct TimeoutError: Error {}
    throw TimeoutError()
  }

  func testSendSimpleMessage_callsOnFinishWithMessageAndMessages() async throws {
    let ids = IDGenerator()
    let captured = RequestCapture()

    let finishCapture = FinishCapture()

    let session = ChatSession(.init(
      id: "123",
      requestStream: { chatID, messages, trigger, messageID, options, _ in
        await captured.record(chatID: chatID, messages: messages, trigger: trigger, messageID: messageID, options: options)

        return AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          Task {
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.textStart(id: "text-1"))
            continuation.yield(.textDelta(id: "text-1", delta: "Hello"))
            continuation.yield(.textDelta(id: "text-1", delta: ","))
            continuation.yield(.textDelta(id: "text-1", delta: " world"))
            continuation.yield(.textDelta(id: "text-1", delta: "."))
            continuation.yield(.textEnd(id: "text-1"))
            continuation.yield(.finishStep)
            continuation.yield(.finish(finishReason: .stop))
            continuation.finish()
          }
        }
      },
      onFinish: { event in await finishCapture.set(event) },
      generateID: { ids.nextID() }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]))

    let maybeFinishEvent = await finishCapture.snapshot()
    let event = try XCTUnwrap(maybeFinishEvent)
    XCTAssertEqual(event.isAbort, false)
    XCTAssertEqual(event.isDisconnect, false)
    XCTAssertEqual(event.isError, false)
    XCTAssertEqual(event.finishReason, .stop)

    XCTAssertEqual(event.messages, [
      .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
      .init(id: "id-1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "text-1", text: "Hello, world.", state: .done)),
      ]),
    ])

    XCTAssertEqual(event.message, .init(id: "id-1", role: .assistant, parts: [
      .stepStart,
      .text(.init(id: "text-1", text: "Hello, world.", state: .done)),
    ]))

    let maybeRequest = await captured.snapshot()
    let request = try XCTUnwrap(maybeRequest)
    XCTAssertEqual(request.chatID, "123")
    XCTAssertEqual(request.trigger, .submitMessage)
    XCTAssertEqual(request.messageID, nil)
    XCTAssertEqual(request.messages, [
      .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
    ])
  }

  func testSendSimpleMessage_updatesMessagesDuringStreaming() async throws {
    let ids = IDGenerator()
    let history = MessageHistory()

    let session = ChatSession(.init(
      id: "123",
      requestStream: { _, _, _, _, _, _ in
        AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          Task {
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.textStart(id: "text-1"))
            continuation.yield(.textDelta(id: "text-1", delta: "Hello"))
            continuation.yield(.textDelta(id: "text-1", delta: ","))
            continuation.yield(.textDelta(id: "text-1", delta: " world"))
            continuation.yield(.textDelta(id: "text-1", delta: "."))
            continuation.yield(.textEnd(id: "text-1"))
            continuation.yield(.finishStep)
            continuation.yield(.finish(finishReason: .stop))
            continuation.finish()
          }
        }
      },
      // Assert the raw transport→reducer cadence; the smoothing funnel is covered by StreamSmoothingTests.
      generateID: { ids.nextID() },
      smoothing: .disabled
    ))

    let updates = await session.updates(bufferingPolicy: .unbounded)
    let collectTask = Task {
      var lastMessages: [ChatMessage]? = nil
      for await snapshot in updates {
        guard snapshot.messages != lastMessages else { continue }
        lastMessages = snapshot.messages
        await history.append(snapshot.messages)

        if snapshot.messages.count == 2,
           let assistant = snapshot.messages.last,
           assistant.role == .assistant,
           assistant.parts.contains(where: { part in
             guard case let .text(text) = part else { return false }
             return text.state == .done && text.text == "Hello, world."
           }) {
          break
        }
      }
    }

    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]))
    }

    _ = await sendTask.value
    _ = await collectTask.value

    let historySnapshot = await history.snapshot()
    XCTAssertEqual(historySnapshot, [
      [],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
      ],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .text(.init(id: "text-1", text: "", state: .streaming)),
        ]),
      ],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .text(.init(id: "text-1", text: "Hello", state: .streaming)),
        ]),
      ],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .text(.init(id: "text-1", text: "Hello,", state: .streaming)),
        ]),
      ],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .text(.init(id: "text-1", text: "Hello, world", state: .streaming)),
        ]),
      ],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .text(.init(id: "text-1", text: "Hello, world.", state: .streaming)),
        ]),
      ],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .text(.init(id: "text-1", text: "Hello, world.", state: .done)),
        ]),
      ],
    ])
  }

  func testDataUIPart_nonTransient_isAddedToAssistantMessage_andCallsOnData() async throws {
    let ids = IDGenerator()
    let dataCapture = DataCapture()

    let session = ChatSession(.init(
      id: "123",
      onData: { part in await dataCapture.append(part) },
      requestStream: { _, _, _, _, _, _ in
        AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          Task {
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.data(.init(type: "data-test", data: .string("example-data-can-be-anything"))))
            continuation.yield(.finishStep)
            continuation.yield(.finish(finishReason: .stop))
            continuation.finish()
          }
        }
      },
      generateID: { ids.nextID() }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "hi", state: .done))]))

    let messages = await session.messages
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages[1].role, .assistant)
    XCTAssertEqual(messages[1].parts, [
      .stepStart,
      .data(.init(type: "data-test", data: .string("example-data-can-be-anything"))),
    ])

    let dataParts = await dataCapture.snapshot()
    XCTAssertEqual(dataParts, [
      .init(type: "data-test", id: nil, data: .string("example-data-can-be-anything"), transient: nil),
    ])
  }

  func testDataUIPart_transient_isNotAddedToAssistantMessage_butCallsOnData() async throws {
    let ids = IDGenerator()
    let dataCapture = DataCapture()

    let session = ChatSession(.init(
      id: "123",
      onData: { part in await dataCapture.append(part) },
      requestStream: { _, _, _, _, _, _ in
        AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          Task {
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.data(.init(type: "data-test", data: .string("example-data-can-be-anything"), transient: true)))
            continuation.yield(.finishStep)
            continuation.yield(.finish(finishReason: .stop))
            continuation.finish()
          }
        }
      },
      generateID: { ids.nextID() }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "hi", state: .done))]))

    let messages = await session.messages
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages[1].role, .assistant)
    XCTAssertEqual(messages[1].parts, [.stepStart])

    let dataParts = await dataCapture.snapshot()
    XCTAssertEqual(dataParts, [
      .init(type: "data-test", id: nil, data: .string("example-data-can-be-anything"), transient: true),
    ])
  }

  func testValidateMessageMetadata_whenInvalid_setsErrorStatus_andCallsOnErrorAndOnFinish() async throws {
    let ids = IDGenerator()
    let finishCapture = FinishCapture()
    let errors = StreamErrorCapture()

    let session = ChatSession(.init(
      id: "123",
      validateMessageMetadata: { value in
        guard case let .object(obj) = value,
              case .string = obj["metadata"] else {
          throw ValidationError()
        }
      },
      requestStream: { _, _, _, _, _, _ in
        AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          Task {
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.textStart(id: "t1"))
            continuation.yield(.textDelta(id: "t1", delta: "Hello"))
            continuation.yield(.textEnd(id: "t1"))
            continuation.yield(.messageMetadata(.number(1)))
            continuation.finish()
          }
        }
      },
      onError: { error in await errors.append(error) },
      onFinish: { event in await finishCapture.set(event) },
      generateID: { ids.nextID() }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "hi", state: .done))]))

    let status = await session.status
    XCTAssertEqual(status, .error)

    let errorList = await errors.snapshot()
    XCTAssertEqual(errorList.compactMap { $0 as? ValidationError }, [ValidationError()])

    let maybeFinishEvent = await finishCapture.snapshot()
    let finishEvent = try XCTUnwrap(maybeFinishEvent)
    XCTAssertEqual(finishEvent.isError, true)
    XCTAssertEqual(finishEvent.isAbort, false)
    XCTAssertEqual(finishEvent.isDisconnect, false)
  }

  func testValidateDataParts_whenInvalid_setsErrorStatus_andCallsOnErrorAndOnFinish() async throws {
    let ids = IDGenerator()
    let finishCapture = FinishCapture()
    let errors = StreamErrorCapture()

    let session = ChatSession(.init(
      id: "123",
      validateDataParts: [
        "data-test": { value in
          guard case .string = value else { throw ValidationError() }
        },
      ],
      requestStream: { _, _, _, _, _, _ in
        AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          Task {
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.textStart(id: "t1"))
            continuation.yield(.textDelta(id: "t1", delta: "Hello"))
            continuation.yield(.textEnd(id: "t1"))
            continuation.yield(.data(.init(type: "data-test", data: .object(["k": .string("v")]))))
            continuation.finish()
          }
        }
      },
      onError: { error in await errors.append(error) },
      onFinish: { event in await finishCapture.set(event) },
      generateID: { ids.nextID() }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "hi", state: .done))]))

    let status = await session.status
    XCTAssertEqual(status, .error)

    let errorList = await errors.snapshot()
    XCTAssertEqual(errorList.compactMap { $0 as? ValidationError }, [ValidationError()])

    let maybeFinishEvent = await finishCapture.snapshot()
    let finishEvent = try XCTUnwrap(maybeFinishEvent)
    XCTAssertEqual(finishEvent.isError, true)
    XCTAssertEqual(finishEvent.isAbort, false)
    XCTAssertEqual(finishEvent.isDisconnect, false)
  }

  func testSend_appendsUserMessageAndStreamsAssistantText() async {
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          continuation.yield(.streamStart())
          continuation.yield(.startStep())
          continuation.yield(.textStart(id: "t1"))
          continuation.yield(.textDelta(id: "t1", text: "Hello"))
          continuation.yield(.textEnd(id: "t1"))
          continuation.yield(.finishStep(finishReason: .stop))
          continuation.yield(.finish(finishReason: .stop))
          continuation.finish()
        }
      }
    )

    let session = ChatSession(.init(model: model, generateID: {
      "id-\(UUID().uuidString)"
    }))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "hi", state: .done))]))

    let messages = await session.messages
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages[0].role, .user)
    XCTAssertEqual(messages[1].role, .assistant)

    let assistantParts = messages[1].parts
    XCTAssertTrue(assistantParts.contains(where: { if case .stepStart = $0 { return true }; return false }))
    let text = assistantParts.compactMap { part -> String? in
      guard case let .text(t) = part else { return nil }
      return t.text
    }.joined()
    XCTAssertEqual(text, "Hello")
    let status = await session.status
    XCTAssertEqual(status, .ready)
  }

  func testSend_convertDataPart_convertsUserDataPartsBeforeCallingModel() async throws {
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          continuation.yield(.streamStart())
          continuation.yield(.startStep())
          continuation.yield(.textStart(id: "t1"))
          continuation.yield(.textDelta(id: "t1", text: "OK"))
          continuation.yield(.textEnd(id: "t1"))
          continuation.yield(.finishStep(finishReason: .stop))
          continuation.yield(.finish(finishReason: .stop))
          continuation.finish()
        }
      }
    )

    let session = ChatSession(.init(
      model: model,
      convertDataPart: { part in
        guard part.type == "data-url" else { return nil }
        guard case let .object(obj) = part.data else { return nil }
        guard case let .string(url)? = obj["url"] else { return nil }
        return .text(.init(text: url))
      }
    ))

    await session.send(.init(
      role: .user,
      parts: [
        .data(.init(type: "data-url", data: .object(["url": .string("https://example.com")]))),
        .text(.init(id: "u", text: "hi", state: .done)),
      ]
    ))

    let requests = model.recordedRequests()
    let request = try XCTUnwrap(requests.first)
    let userMessage = try XCTUnwrap(request.messages.last(where: { $0.role == .user }))

    let textParts = userMessage.content.compactMap { part -> String? in
      guard case let .text(text) = part else { return nil }
      return text.text
    }
    XCTAssertEqual(textParts, ["https://example.com", "hi"])
  }

  func testSend_withReplaceMessageID_replacesUserMessageAndTruncates() async {
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          continuation.yield(.streamStart())
          continuation.yield(.startStep())
          continuation.yield(.textStart(id: "t1"))
          continuation.yield(.textDelta(id: "t1", text: "OK"))
          continuation.yield(.textEnd(id: "t1"))
          continuation.yield(.finishStep(finishReason: .stop))
          continuation.yield(.finish(finishReason: .stop))
          continuation.finish()
        }
      }
    )

    let session = ChatSession(.init(model: model, messages: [
      .init(id: "u1", role: .user, parts: [.text(.init(id: "u-text", text: "old", state: .done))]),
      .init(id: "a1", role: .assistant, parts: [.text(.init(id: "a-text", text: "prev", state: .done))]),
      .init(id: "u2", role: .user, parts: [.text(.init(id: "u2-text", text: "later", state: .done))]),
    ]))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "new", state: .done))], replaceMessageID: "u1"))

    let messages = await session.messages
    XCTAssertEqual(messages[0].id, "u1")
    let userText = messages[0].parts.compactMap { part -> String? in
      guard case let .text(t) = part else { return nil }
      return t.text
    }.joined()
    XCTAssertEqual(userText, "new")

    // Truncates everything after u1 before regenerating response.
    XCTAssertEqual(messages[0].role, .user)
    XCTAssertEqual(messages[1].role, .assistant)
    XCTAssertEqual(messages.count, 2)
  }

  func testSendAutomaticallyWhen_doesNotAutoSubmitWhileStreaming_thenSubmitsAfterFinish() async throws {
    let streams = StreamQueue()
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          Task { await streams.enqueue(continuation) }
        }
      }
    )

    let session = ChatSession(.init(
      model: model,
      sendAutomaticallyWhen: { _ in true },
      generateID: { "id-0" }
    ))

    // Start request (stream 0) and emit tool call but do not finish stream.
    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))
    }

    // Wait until first stream is created.
    for _ in 0..<200 {
      if await streams.count() >= 1 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    let c0 = await streams.continuation(at: 0)
    XCTAssertNotNil(c0)

    c0?.yield(.streamStart())
    c0?.yield(.startStep())
    c0?.yield(.toolCall(.init(toolCallID: "tool-1", toolName: "getLocation", inputJSON: "{}", input: .object([:]))))

    try await waitUntil {
      let messages = await session.messages
      guard messages.count == 2, messages[1].role == .assistant else { return false }
      return messages[1].parts.contains(where: { part in
        guard case let .tool(tool) = part else { return false }
        return tool.toolCallID == "tool-1"
      })
    }

    // While streaming, adding tool output must not auto-submit.
    await session.addToolOutput(tool: ToolID<[String: String], String>("getLocation"), toolCallID: "tool-1", output: "NYC")

    let messagesAfterToolOutput = await session.messages
    XCTAssertTrue(messagesAfterToolOutput.count >= 2)
    XCTAssertEqual(messagesAfterToolOutput.last?.role, .assistant)
    XCTAssertTrue(messagesAfterToolOutput.last?.parts.contains(where: { part in
      guard case let .tool(tool) = part else { return false }
      guard tool.toolCallID == "tool-1" else { return false }
      return tool.output == .string("NYC") && tool.state == .outputAvailable(preliminary: false)
    }) ?? false)

    // Ensure only one request so far.
    XCTAssertEqual(model.recordedRequests().count, 1)

    // Finish stream 0; now auto-submit should trigger (stream 1 created).
    c0?.yield(.finishStep(finishReason: .toolCalls))
    c0?.yield(.finish(finishReason: .toolCalls))
    c0?.finish()

    for _ in 0..<500 {
      if model.recordedRequests().count >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertEqual(model.recordedRequests().count, 2)

    // Complete stream 1 to avoid leaking tasks.
    for _ in 0..<200 {
      if await streams.count() >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    let c1 = await streams.continuation(at: 1)
    XCTAssertNotNil(c1)
    c1?.yield(.streamStart())
    c1?.yield(.startStep())
    c1?.yield(.finishStep(finishReason: .stop))
    c1?.yield(.finish(finishReason: .stop))
    c1?.finish()

    _ = await sendTask.value
  }

  func testSendAutomaticallyWhen_dynamicToolOutput_submitsSecondRequest_andAppendsSecondStepTextToAssistantMessage() async throws {
    let streams = StreamQueue()
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          Task { await streams.enqueue(continuation) }
        }
      }
    )

    let session = ChatSession(.init(
      model: model,
      sendAutomaticallyWhen: { messages in
        ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages)
      }
    ))

    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))
    }

    for _ in 0..<200 {
      if await streams.count() >= 1 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    let c0 = await streams.continuation(at: 0)
    c0?.yield(.streamStart())
    c0?.yield(.startStep())
    c0?.yield(.toolCall(.init(
      toolCallID: "tool-1",
      toolName: "test-tool",
      inputJSON: "{}",
      input: .object(["testArg": .string("test-value")]),
      dynamic: true
    )))
    c0?.yield(.finishStep(finishReason: .toolCalls))
    c0?.yield(.finish(finishReason: .toolCalls))
    c0?.finish()

    _ = await sendTask.value

    await session.addToolOutput(tool: ToolID<EmptyInput, String>("test-tool"), toolCallID: "tool-1", output: "test-output")

    for _ in 0..<500 {
      if model.recordedRequests().count >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertEqual(model.recordedRequests().count, 2)

    for _ in 0..<200 {
      if await streams.count() >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    // Stream the second response (should be appended to the existing assistant message as a new step).
    let c1 = await streams.continuation(at: 1)
    XCTAssertNotNil(c1)
    c1?.yield(.streamStart())
    c1?.yield(.startStep())
    c1?.yield(.textStart(id: "t1"))
    c1?.yield(.textDelta(id: "t1", text: "test-delta"))
    c1?.yield(.textEnd(id: "t1"))
    c1?.yield(.finishStep(finishReason: .stop))
    c1?.yield(.finish(finishReason: .stop))
    c1?.finish()

    try await waitUntil {
      let messages = await session.messages
      guard messages.count == 2, messages[1].role == .assistant else { return false }
      return messages[1].parts.contains(where: { part in
        guard case let .text(text) = part else { return false }
        return text.text == "test-delta" && text.state == .done
      })
    }

    let finalMessages = await session.messages
    XCTAssertEqual(finalMessages.count, 2)
    XCTAssertEqual(finalMessages[1].role, .assistant)

    let assistantParts = finalMessages[1].parts
    XCTAssertEqual(assistantParts.filter { $0 == .stepStart }.count, 2)

    XCTAssertTrue(assistantParts.contains(where: { part in
      guard case let .tool(tool) = part else { return false }
      return tool.toolCallID == "tool-1" &&
        tool.toolName == "test-tool" &&
        tool.dynamic == true &&
        tool.output == .string("test-output")
    }))

    let text = assistantParts.compactMap { part -> ChatTextPart? in
      guard case let .text(text) = part else { return nil }
      return text
    }.last
    XCTAssertEqual(text?.text, "test-delta")
    XCTAssertEqual(text?.state, .done)
  }

  func testSendAutomaticallyWhen_dynamicToolOutput_insertsImplicitStepStartsWhenStreamOmitsStepMarkers() async throws {
    let streams = StreamQueue()
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          Task { await streams.enqueue(continuation) }
        }
      }
    )

    let session = ChatSession(.init(
      model: model,
      sendAutomaticallyWhen: { messages in
        ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages)
      }
    ))

    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))
    }

    for _ in 0..<200 {
      if await streams.count() >= 1 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    let c0 = await streams.continuation(at: 0)
    c0?.yield(.streamStart())
    c0?.yield(.toolCall(.init(
      toolCallID: "tool-1",
      toolName: "test-tool",
      inputJSON: "{}",
      input: .object(["testArg": .string("test-value")]),
      dynamic: true
    )))
    c0?.yield(.finish(finishReason: .toolCalls))
    c0?.finish()

    _ = await sendTask.value

    await session.addToolOutput(tool: ToolID<EmptyInput, String>("test-tool"), toolCallID: "tool-1", output: "test-output")

    for _ in 0..<500 {
      if model.recordedRequests().count >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertEqual(model.recordedRequests().count, 2)

    for _ in 0..<200 {
      if await streams.count() >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    let c1 = await streams.continuation(at: 1)
    XCTAssertNotNil(c1)
    c1?.yield(.streamStart())
    c1?.yield(.textStart(id: "t1"))
    c1?.yield(.textDelta(id: "t1", text: "implicit-step"))
    c1?.yield(.textEnd(id: "t1"))
    c1?.yield(.finish(finishReason: .stop))
    c1?.finish()

    try await waitUntil {
      let messages = await session.messages
      guard messages.count == 2, messages[1].role == .assistant else { return false }
      return messages[1].parts.contains(where: { part in
        guard case let .text(text) = part else { return false }
        return text.text == "implicit-step" && text.state == .done
      })
    }

    let finalMessages = await session.messages
    XCTAssertEqual(finalMessages.count, 2)
    XCTAssertEqual(finalMessages[1].role, .assistant)

    let assistantParts = finalMessages[1].parts
    XCTAssertEqual(assistantParts.filter { $0 == .stepStart }.count, 2)

    XCTAssertTrue(assistantParts.contains(where: { part in
      guard case let .tool(tool) = part else { return false }
      return tool.toolCallID == "tool-1" &&
        tool.toolName == "test-tool" &&
        tool.dynamic == true &&
        tool.output == .string("test-output")
    }))
  }

  func testStop_cancelsInFlightRequestAndReturnsToReady() async throws {
    let streams = StreamQueue()
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          Task { await streams.enqueue(continuation) }
        }
      }
    )

    let session = ChatSession(.init(model: model))

    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))
    }

    for _ in 0..<200 {
      if await streams.count() >= 1 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    let c0 = await streams.continuation(at: 0)
    c0?.yield(.streamStart())
    c0?.yield(.startStep())
    c0?.yield(.textStart(id: "t1"))
    c0?.yield(.textDelta(id: "t1", text: "Hello"))

    await session.stop()

    // Let the underlying stream observe cancellation.
    c0?.yield(.textDelta(id: "t1", text: " world"))
    c0?.finish()

    for _ in 0..<200 {
      let status = await session.status
      if status == .ready { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    let finalStatus = await session.status
    XCTAssertEqual(finalStatus, .ready)
    _ = await sendTask.value
  }

  func testClearError_resetsErrorStateToReady() async throws {
    struct TestError: Error {}

    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          continuation.finish(throwing: TestError())
        }
      }
    )

    let session = ChatSession(.init(model: model))
    await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))

    let errorStatus = await session.status
    XCTAssertEqual(errorStatus, .error)
    await session.clearError()
    let readyStatus = await session.status
    XCTAssertEqual(readyStatus, .ready)
  }

  func testClearError_afterErrorPart_clearsErrorAndSetsStatusReady() async throws {
    let session = ChatSession(.init(
      requestStream: { _, _, _, _, _, _ in
        AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          continuation.yield(.start())
          continuation.yield(.error("test-error"))
          continuation.finish()
        }
      },
      onError: { _ in },
      generateID: { "id-0" }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "Hello", state: .done))]))

    let statusAfter = await session.status
    XCTAssertEqual(statusAfter, .error)
    let errorAfter = await session.error
    XCTAssertNotNil(errorAfter)

    await session.clearError()

    let statusReady = await session.status
    XCTAssertEqual(statusReady, .ready)
    let errorCleared = await session.error
    XCTAssertNil(errorCleared)
  }

  func testResumeStream_whenReconnectReturnsNil_setsReadyAndDoesNotMutateMessages() async {
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in AsyncThrowingStream(ModelStreamPart.self) { $0.finish() } }
    )

    let session = ChatSession(.init(
      id: "chat-1",
      model: model,
      reconnectToStream: { _, _ in nil }
    ))

    await session.resumeStream()

    let status = await session.status
    XCTAssertEqual(status, .ready)
    let messages = await session.messages
    XCTAssertEqual(messages.count, 0)
  }

  func testResumeStream_whenReconnectReturnsStream_appliesStreamPartsToMessages() async {
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in AsyncThrowingStream(ModelStreamPart.self) { $0.finish() } }
    )

    let session = ChatSession(.init(
      id: "chat-1",
      model: model,
      reconnectToStream: { _, _ in
        AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          continuation.yield(.start())
          continuation.yield(.startStep)
          continuation.yield(.textStart(id: "t1"))
          continuation.yield(.textDelta(id: "t1", delta: "Hello"))
          continuation.yield(.textEnd(id: "t1"))
          continuation.yield(.finishStep)
          continuation.yield(.finish(finishReason: .stop))
          continuation.finish()
        }
      }
    ))

    await session.resumeStream()

    let messages = await session.messages
    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(messages[0].role, .assistant)

    let text = messages[0].parts.compactMap { part -> String? in
      guard case let .text(t) = part else { return nil }
      return t.text
    }.joined()
    XCTAssertEqual(text, "Hello")
  }

  func testUpdates_emitsSnapshotsAsMessagesChange() async throws {
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          continuation.yield(.streamStart())
          continuation.yield(.startStep())
          continuation.yield(.textStart(id: "t1"))
          continuation.yield(.textDelta(id: "t1", text: "Hello"))
          continuation.yield(.textEnd(id: "t1"))
          continuation.yield(.finishStep(finishReason: .stop))
          continuation.yield(.finish(finishReason: .stop))
          continuation.finish()
        }
      }
    )

    let session = ChatSession(.init(model: model, generateID: { "id-0" }))
    let stream = await session.updates(bufferingPolicy: .unbounded)

    let collector = Task { () -> [ChatSessionSnapshot] in
      var snapshots: [ChatSessionSnapshot] = []
      for await snap in stream {
        snapshots.append(snap)
        if snap.status == .ready, snap.messages.count == 2 {
          break
        }
      }
      return snapshots
    }

    await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))

    let snapshots = await collector.value
    XCTAssertTrue(snapshots.contains(where: { $0.messages.count == 1 && $0.messages.first?.role == .user }))
    XCTAssertTrue(snapshots.contains(where: { $0.messages.count == 2 && $0.messages.last?.role == .assistant }))
    XCTAssertTrue(snapshots.contains(where: { $0.status == .streaming }) || snapshots.contains(where: { $0.status == .submitted }))
  }

  func testAddToolApprovalResponse_updatesLastAssistantToolPart() async {
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in AsyncThrowingStream(ModelStreamPart.self) { $0.finish() } }
    )

    let session = ChatSession(.init(model: model, messages: [
      .init(id: "a1", role: .assistant, parts: [
        .tool(.init(
          toolCallID: "tool-1",
          toolName: "getWeather",
          input: .object(["city": .string("SF")]),
          state: .approvalRequested(approvalID: "approval-1")
        )),
      ]),
    ]))

    await session.addToolApprovalResponse(approvalID: "approval-1", approved: true, reason: nil)
    let messages = await session.messages
    guard let assistant = messages.last else { return XCTFail("missing assistant") }
    guard case let .tool(tool)? = assistant.parts.first else { return XCTFail("missing tool part") }
    XCTAssertEqual(tool.approval, .init(id: "approval-1", approved: true, reason: nil))
    if case let .approvalResponded(approvalID, approved, _) = tool.state {
      XCTAssertEqual(approvalID, "approval-1")
      XCTAssertEqual(approved, true)
    } else {
      XCTFail("expected approvalResponded state")
    }
  }

  func testAddToolApprovalResponse_approved_updatesToolApprovalObject() async {
    let session = ChatSession(.init(
      messages: [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u", text: "What is the weather in Tokyo?", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .tool(.init(
            toolCallID: "call-1",
            toolName: "weather",
            providerExecuted: false,
            dynamic: false,
            input: .object(["city": .string("Tokyo")]),
            approval: .init(id: "approval-1"),
            state: .approvalRequested(approvalID: "approval-1")
          )),
        ]),
      ]
    ))

    await session.addToolApprovalResponse(approvalID: "approval-1", approved: true, reason: nil)

    let messages = await session.messages
    XCTAssertEqual(messages.count, 2)
    guard let assistant = messages.last else { return XCTFail("missing assistant") }

    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).first else { return XCTFail("missing tool") }

    XCTAssertEqual(tool.approval, .init(id: "approval-1", approved: true, reason: nil))
    XCTAssertEqual(tool.state, .approvalResponded(approvalID: "approval-1", approved: true, reason: nil))
  }

  func testAddToolOutput_updatesToolPartNotInLastAssistantMessage_andEmitsUpdate() async throws {
    actor SnapshotLog {
      private var snapshots: [ChatSessionSnapshot] = []
      func append(_ snapshot: ChatSessionSnapshot) { snapshots.append(snapshot) }
      func count() -> Int { snapshots.count }
      func snapshot() -> [ChatSessionSnapshot] { snapshots }
    }

    let session = ChatSession(.init(
      messages: [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .tool(.init(
            toolCallID: "tool-1",
            toolName: "test-tool",
            input: .object(["a": .string("b")]),
            state: .inputAvailable
          )),
        ]),
        .init(id: "id-2", role: .assistant, parts: [.text(.init(id: "t", text: "later message", state: .done))]),
      ]
    ))

    let log = SnapshotLog()
    let stream = await session.updates(bufferingPolicy: .unbounded)
    let collectTask = Task {
      for await snap in stream {
        await log.append(snap)
        if await log.count() >= 2 { break }
      }
    }

    try await waitUntil { (await log.count()) >= 1 }

    await session.addToolOutput(
      tool: ToolID<EmptyInput, String>("test-tool"),
      toolCallID: "tool-1",
      output: "new-output"
    )

    try await waitUntil { (await log.count()) >= 2 }
    await collectTask.value

    let messages = await session.messages
    XCTAssertEqual(messages.count, 3)

    guard case let .tool(toolPart)? = messages[1].parts.first else {
      return XCTFail("missing tool part")
    }

    XCTAssertEqual(toolPart.output, .string("new-output"))
    XCTAssertEqual(toolPart.state, .outputAvailable(preliminary: false))

    let snapshots = await log.snapshot()
    XCTAssertTrue(snapshots.contains(where: { snap in
      snap.messages.contains(where: { message in
        message.parts.contains(where: { part in
          guard case let .tool(tool) = part else { return false }
          return tool.toolCallID == "tool-1" &&
            tool.output == .string("new-output") &&
            tool.state == .outputAvailable(preliminary: false)
        })
      })
    }))
  }

  func testAddToolApprovalResponse_approved_withAutomaticSending_streamsToolResultAndText() async throws {
    let finishCapture = FinishCapture()

    actor CallCounter {
      var count = 0
      func next() -> Int { count += 1; return count }
      func current() -> Int { count }
    }
    let calls = CallCounter()

    let session = ChatSession(.init(
      sendAutomaticallyWhen: { messages in
        ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithApprovalResponses(messages: messages)
      },
      requestStream: { _, _, _, _, _, _ in
        let callNumber = await calls.next()
        XCTAssertEqual(callNumber, 1, "Expected only one request after approval response triggers auto-submit.")

        return AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          continuation.yield(.start())
          continuation.yield(.startStep)
          continuation.yield(.toolOutputAvailable(.init(
            toolCallID: "call-1",
            output: .object(["temperature": .number(72), "weather": .string("sunny")]),
            preliminary: false
          )))
          continuation.yield(.textStart(id: "txt-1"))
          continuation.yield(.textDelta(id: "txt-1", delta: "The weather in Tokyo is sunny."))
          continuation.yield(.textEnd(id: "txt-1"))
          continuation.yield(.finishStep)
          continuation.yield(.finish(finishReason: .stop))
          continuation.finish()
        }
      },
      onFinish: { event in await finishCapture.set(event) },
      generateID: { "newid-0" },
      messages: [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u", text: "What is the weather in Tokyo?", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .tool(.init(
            toolCallID: "call-1",
            toolName: "weather",
            providerExecuted: false,
            dynamic: false,
            input: .object(["city": .string("Tokyo")]),
            approval: .init(id: "approval-1"),
            state: .approvalRequested(approvalID: "approval-1")
          )),
        ]),
      ]
    ))

    await session.addToolApprovalResponse(approvalID: "approval-1", approved: true, reason: nil)

    try await waitUntil { (await finishCapture.snapshot()) != nil }

    let messages = await session.messages
    XCTAssertEqual(messages.count, 2)
    let assistant = messages[1]
    XCTAssertEqual(assistant.role, .assistant)

    XCTAssertEqual(assistant.parts.filter { $0 == .stepStart }.count, 2)

    guard let tool = assistant.parts.compactMap({ part -> ChatToolPart? in
      guard case let .tool(tool) = part else { return nil }
      return tool
    }).first else { return XCTFail("missing tool") }

    XCTAssertEqual(tool.approval, .init(id: "approval-1", approved: true, reason: nil))
    XCTAssertEqual(tool.output, .object(["temperature": .number(72), "weather": .string("sunny")]))
    XCTAssertEqual(tool.state, .outputAvailable(preliminary: false))

    guard let finalText = assistant.parts.compactMap({ part -> ChatTextPart? in
      guard case let .text(text) = part else { return nil }
      return text
    }).last else { return XCTFail("missing final text") }
    XCTAssertEqual(finalText.text, "The weather in Tokyo is sunny.")
    XCTAssertEqual(finalText.state, .done)

    let callCount = await calls.current()
    XCTAssertEqual(callCount, 1)
  }

  func testAddToolOutput_whenCompleteWithToolCalls_autoSubmitsNewRequest() async throws {
    let streams = StreamQueue()
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          Task { await streams.enqueue(continuation) }
        }
      }
    )

    let session = ChatSession(.init(
      model: model,
      sendAutomaticallyWhen: { messages in
        ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages)
      },
      generateID: { "id-0" }
    ))

    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))
    }

    for _ in 0..<200 {
      if await streams.count() >= 1 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    let c0 = await streams.continuation(at: 0)
    c0?.yield(.streamStart())
    c0?.yield(.startStep())
    c0?.yield(.toolCall(.init(
      toolCallID: "tool-1",
      toolName: "test-tool",
      inputJSON: "{\"a\":\"b\"}",
      input: nil,
      dynamic: true
    )))
    c0?.yield(.finishStep(finishReason: .toolCalls))
    c0?.yield(.finish(finishReason: .toolCalls))
    c0?.finish()

    _ = await sendTask.value

    XCTAssertEqual(model.recordedRequests().count, 1)

    await session.addToolOutput(tool: ToolID<EmptyInput, String>("test-tool"), toolCallID: "tool-1", output: "test-output")

    for _ in 0..<500 {
      if model.recordedRequests().count >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertEqual(model.recordedRequests().count, 2)

    // Finish the auto-submitted request.
    let c1 = await streams.continuation(at: 1)
    c1?.yield(.streamStart())
    c1?.yield(.startStep())
    c1?.yield(.finishStep(finishReason: .stop))
    c1?.yield(.finish(finishReason: .stop))
    c1?.finish()

    // The 2nd request should include a tool-role message with toolResult.
    let second = model.recordedRequests()[1]
    let foundToolResult = second.messages.contains(where: { message in
      guard message.role == .tool else { return false }
      return message.content.contains(where: { part in
        if case let .toolResult(result) = part {
          return result.toolCallID == "tool-1" &&
            result.output == .object(["type": .string("text"), "value": .string("test-output")])
        }
        return false
      })
    })
    if foundToolResult == false {
      XCTFail("Expected tool result in 2nd request. Messages: \(second.messages)")
    }
  }

  func testAddToolResult_likeUseChat_addToolOutput_autoSubmitsAndSendsTranscript() async throws {
    actor RequestLog {
      var calls: [[ChatMessage]] = []
      func append(_ messages: [ChatMessage]) { calls.append(messages) }
      func snapshot() -> [[ChatMessage]] { calls }
    }
    let log = RequestLog()

    actor CallCounter {
      var count = 0
      func next() -> Int { count += 1; return count }
    }
    let counter = CallCounter()
    let ids = IDGenerator()

    let session = ChatSession(.init(
      sendAutomaticallyWhen: { messages in
        ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages)
      },
      requestStream: { _, messages, trigger, messageID, _, _ in
        let callNumber = await counter.next()
        await log.append(messages)

        if callNumber == 1 {
          XCTAssertEqual(trigger, .submitMessage)
          XCTAssertNil(messageID)
          return AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.toolInputAvailable(.init(
              toolCallID: "tool-call-0",
              toolName: "test-tool",
              input: .object(["testArg": .string("test-value")]),
              providerExecuted: nil,
              providerMetadata: nil,
              dynamic: false,
              title: nil
            )))
            continuation.yield(.finishStep)
            continuation.yield(.finish(finishReason: .toolCalls))
            continuation.finish()
          }
        } else {
          XCTAssertEqual(trigger, .submitMessage)
          XCTAssertEqual(messageID, "id-1")
          return AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.finishStep)
            continuation.yield(.finish(finishReason: .stop))
            continuation.finish()
          }
        }
      },
      generateID: { ids.nextID() }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "Hello, world!", state: .done))]))

    // UI should show tool call.
    try await waitUntil {
      let messages = await session.messages
      guard messages.count == 2, messages[1].role == .assistant else { return false }
      return messages[1].parts.contains(where: { part in
        guard case let .tool(tool) = part else { return false }
        return tool.toolCallID == "tool-call-0" && tool.state == .inputAvailable
      })
    }

    // Submit tool result -> triggers auto-submit.
    await session.addToolOutput(tool: ToolID<EmptyInput, String>("test-tool"), toolCallID: "tool-call-0", output: "test-output")

    try await waitUntil {
      let calls = await log.snapshot()
      return calls.count >= 2
    }

    let messagesAfter = await session.messages
    XCTAssertEqual(messagesAfter.count, 2)
    XCTAssertEqual(messagesAfter[1].role, .assistant)
    XCTAssertTrue(messagesAfter[1].parts.contains(where: { part in
      guard case let .tool(tool) = part else { return false }
      return tool.toolCallID == "tool-call-0" &&
        tool.output == .string("test-output") &&
        tool.state == .outputAvailable(preliminary: false)
    }))

    let callsSnapshot = await log.snapshot()
    XCTAssertEqual(callsSnapshot.count, 2)
    XCTAssertEqual(callsSnapshot[1], [
      .init(id: "id-0", role: .user, parts: [.text(.init(id: "u", text: "Hello, world!", state: .done))]),
      .init(id: "id-1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "tool-call-0",
          toolName: "test-tool",
          providerExecuted: false,
          dynamic: false,
          input: .object(["testArg": .string("test-value")]),
          output: .string("test-output"),
          callProviderMetadata: nil,
          state: .outputAvailable(preliminary: false)
        )),
      ]),
    ])
  }

  func testAddToolOutputError_whenCompleteWithToolCalls_autoSubmitsNewRequest() async throws {
    let streams = StreamQueue()
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          Task { await streams.enqueue(continuation) }
        }
      }
    )

    let session = ChatSession(.init(
      model: model,
      sendAutomaticallyWhen: { messages in
        ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages)
      }
    ))

    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))
    }

    for _ in 0..<200 {
      if await streams.count() >= 1 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    let c0 = await streams.continuation(at: 0)
    c0?.yield(.streamStart())
    c0?.yield(.startStep())
    c0?.yield(.toolCall(.init(
      toolCallID: "tool-1",
      toolName: "test-tool",
      inputJSON: "{}",
      input: nil,
      dynamic: true
    )))
    c0?.yield(.finishStep(finishReason: .toolCalls))
    c0?.yield(.finish(finishReason: .toolCalls))
    c0?.finish()

    _ = await sendTask.value

    await session.addToolOutputError(tool: ToolID<EmptyInput, String>("test-tool"), toolCallID: "tool-1", errorText: "boom")

    for _ in 0..<500 {
      if model.recordedRequests().count >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertEqual(model.recordedRequests().count, 2)

    // Finish the auto-submitted request.
    let c1 = await streams.continuation(at: 1)
    c1?.yield(.streamStart())
    c1?.yield(.startStep())
    c1?.yield(.finishStep(finishReason: .stop))
    c1?.yield(.finish(finishReason: .stop))
    c1?.finish()
  }

  func testSecondRequestError_setsErrorStatusAndDoesNotAppendAssistantResponse() async throws {
    enum TestError: Error { case boom }

    let streams = StreamQueue()

    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        return AsyncThrowingStream(ModelStreamPart.self) { continuation in
          Task { await streams.enqueue(continuation) }
        }
      }
    )

    let session = ChatSession(.init(
      model: model,
      sendAutomaticallyWhen: { messages in
        ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages)
      }
    ))

    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))
    }

    for _ in 0..<200 {
      if await streams.count() >= 1 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    let c0 = await streams.continuation(at: 0)
    c0?.yield(.streamStart())
    c0?.yield(.startStep())
    c0?.yield(.toolCall(.init(
      toolCallID: "tool-1",
      toolName: "test-tool",
      inputJSON: "{}",
      input: nil,
      dynamic: true
    )))
    c0?.yield(.finishStep(finishReason: .toolCalls))
    c0?.yield(.finish(finishReason: .toolCalls))
    c0?.finish()

    _ = await sendTask.value

    let messageCountBefore = (await session.messages).count

    await session.addToolOutput(tool: ToolID<EmptyInput, String>("test-tool"), toolCallID: "tool-1", output: "test-output")

    for _ in 0..<200 {
      if await streams.count() >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    // Fail the second stream immediately.
    let c1 = await streams.continuation(at: 1)
    c1?.finish(throwing: TestError.boom)

    for _ in 0..<200 {
      let status = await session.status
      if status == .error { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }

    let finalStatus = await session.status
    XCTAssertEqual(finalStatus, .error)

    let messageCountAfter = (await session.messages).count
    XCTAssertEqual(messageCountAfter, messageCountBefore)
  }

  func testApprovalAutoSubmit_whenCompleteWithApprovalResponses_submitsNewRequest() async throws {
    let streams = StreamQueue()
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          Task { await streams.enqueue(continuation) }
        }
      }
    )

    let session = ChatSession(.init(
      model: model,
      sendAutomaticallyWhen: { messages in
        ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithApprovalResponses(messages: messages)
      },
      messages: [
        .init(id: "a1", role: .assistant, parts: [
          .stepStart,
          .tool(.init(
            toolCallID: "tool-1",
            toolName: "test-tool",
            providerExecuted: false,
            dynamic: true,
            input: .object(["city": .string("Tokyo")]),
            state: .approvalRequested(approvalID: "approval-1")
          )),
        ]),
      ]
    ))

    await session.addToolApprovalResponse(approvalID: "approval-1", approved: true, reason: nil)

    for _ in 0..<500 {
      if model.recordedRequests().count >= 1 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertEqual(model.recordedRequests().count, 1)

    let c0 = await streams.continuation(at: 0)
    c0?.yield(.streamStart())
    c0?.yield(.startStep())
    c0?.yield(.finishStep(finishReason: .stop))
    c0?.yield(.finish(finishReason: .stop))
    c0?.finish()

    let request = model.recordedRequests()[0]
    XCTAssertTrue(request.messages.contains(where: { $0.role == .tool }))
    XCTAssertTrue(request.messages.contains(where: { message in
      guard message.role == .tool else { return false }
      return message.content.contains(where: { part in
        if case let .toolApprovalResponse(response) = part {
          return response.approvalID == "approval-1" && response.approved == true
        }
        return false
      })
    }))
  }

  func testErrorPart_setsErrorStatus() async {
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          continuation.yield(.streamStart())
          continuation.yield(.error(.init(message: "test-error")))
          continuation.finish()
        }
      }
    )

    let session = ChatSession(.init(model: model))
    await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))

    let status = await session.status
    XCTAssertEqual(status, .error)
  }

  func testApprovalFlow_approved_executesToolBeforeSecondRequest() async throws {
    struct WeatherInput: Codable, Sendable, Equatable { let city: String }
    struct WeatherOutput: Codable, Sendable, Equatable { let temperature: Int; let weather: String }

    let toolID = ToolID<WeatherInput, WeatherOutput>("weather")
    var tools = ToolRegistry()
    tools.register(toolID, .init(
      inputSchema: .manual(jsonSchema: .object(properties: ["city": .string()]), name: "WeatherInput"),
      needsApproval: { _, _ in true },
      execute: { input, _ in
        .final(.init(temperature: 72, weather: "sunny"))
      }
    ))

    let streams = StreamQueue()
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          Task { await streams.enqueue(continuation) }
        }
      }
    )

    let session = ChatSession(.init(
      model: model,
      tools: tools,
      sendAutomaticallyWhen: { messages in
        ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithApprovalResponses(messages: messages)
      }
    ))

    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "What is the weather in Tokyo?", state: .done))]))
    }

    // Stream 0: model requests tool.
    for _ in 0..<200 {
      if await streams.count() >= 1 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    let c0 = await streams.continuation(at: 0)
    c0?.yield(.streamStart())
    c0?.yield(.startStep())
    c0?.yield(.toolCall(.init(
      toolCallID: "call-1",
      toolName: "weather",
      inputJSON: "{\"city\":\"Tokyo\"}",
      input: nil,
      dynamic: false
    )))
    c0?.yield(.finishStep(finishReason: .toolCalls))
    c0?.yield(.finish(finishReason: .toolCalls))
    c0?.finish()

    _ = await sendTask.value

    // UI should now have an approval request with generated approvalID.
    let messagesAfterFirst = await session.messages
    let approvalID: String = {
      guard let assistant = messagesAfterFirst.last(where: { $0.role == .assistant }) else { return "" }
      for part in assistant.parts {
        guard case let .tool(tool) = part else { continue }
        if case let .approvalRequested(id) = tool.state { return id }
      }
      return ""
    }()
    XCTAssertFalse(approvalID.isEmpty)

    // Approve => triggers auto-submit.
    await session.addToolApprovalResponse(approvalID: approvalID, approved: true, reason: nil)

    for _ in 0..<500 {
      if model.recordedRequests().count >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertEqual(model.recordedRequests().count, 2)

    // Request 1 should contain a tool-result produced by StreamText.executeApprovals before calling the model.
    let secondRequest = model.recordedRequests()[1]
    let containsToolResult = secondRequest.messages.contains(where: { message in
      guard message.role == .tool else { return false }
      return message.content.contains(where: { part in
        if case let .toolResult(result) = part {
          return result.toolCallID == "call-1" &&
            result.output == .object([
              "type": .string("json"),
              "value": .object(["temperature": .number(72), "weather": .string("sunny")]),
            ])
        }
        return false
      })
    })
    XCTAssertTrue(containsToolResult, "Expected tool result in second request. Messages: \(secondRequest.messages)")

    // Finish stream 1.
    let c1 = await streams.continuation(at: 1)
    c1?.yield(.streamStart())
    c1?.yield(.startStep())
    c1?.yield(.finishStep(finishReason: .stop))
    c1?.yield(.finish(finishReason: .stop))
    c1?.finish()
  }

  func testApprovalFlow_denied_executesDenialBeforeSecondRequest() async throws {
    struct WeatherInput: Codable, Sendable, Equatable { let city: String }
    struct WeatherOutput: Codable, Sendable, Equatable { let temperature: Int; let weather: String }

    let toolID = ToolID<WeatherInput, WeatherOutput>("weather")
    var tools = ToolRegistry()
    tools.register(toolID, .init(
      inputSchema: .manual(jsonSchema: .object(properties: ["city": .string()]), name: "WeatherInput"),
      needsApproval: { _, _ in true },
      execute: { _, _ in
        .final(.init(temperature: 72, weather: "sunny"))
      }
    ))

    let streams = StreamQueue()
    let model = MockLanguageModel(
      generate: { _ in throw AIKitError.invalidConfiguration("not used") },
      stream: { _ in
        AsyncThrowingStream(ModelStreamPart.self) { continuation in
          Task { await streams.enqueue(continuation) }
        }
      }
    )

    let session = ChatSession(.init(
      model: model,
      tools: tools,
      sendAutomaticallyWhen: { messages in
        ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithApprovalResponses(messages: messages)
      }
    ))

    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "What is the weather in Tokyo?", state: .done))]))
    }

    for _ in 0..<200 {
      if await streams.count() >= 1 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    let c0 = await streams.continuation(at: 0)
    c0?.yield(.streamStart())
    c0?.yield(.startStep())
    c0?.yield(.toolCall(.init(
      toolCallID: "call-1",
      toolName: "weather",
      inputJSON: "{\"city\":\"Tokyo\"}",
      input: nil,
      dynamic: false
    )))
    c0?.yield(.finishStep(finishReason: .toolCalls))
    c0?.yield(.finish(finishReason: .toolCalls))
    c0?.finish()

    _ = await sendTask.value

    let messagesAfterFirst = await session.messages
    let approvalID: String = {
      guard let assistant = messagesAfterFirst.last(where: { $0.role == .assistant }) else { return "" }
      for part in assistant.parts {
        guard case let .tool(tool) = part else { continue }
        if case let .approvalRequested(id) = tool.state { return id }
      }
      return ""
    }()
    XCTAssertFalse(approvalID.isEmpty)

    await session.addToolApprovalResponse(approvalID: approvalID, approved: false, reason: "nope")

    for _ in 0..<500 {
      if model.recordedRequests().count >= 2 { break }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    XCTAssertEqual(model.recordedRequests().count, 2)

    let secondRequest = model.recordedRequests()[1]
    let containsDenied = secondRequest.messages.contains(where: { message in
      guard message.role == .tool else { return false }
      return message.content.contains(where: { part in
        if case let .toolResult(result) = part {
          return result.toolCallID == "call-1" &&
            result.toolName == "weather" &&
            result.output == .object(["type": .string("error-text"), "value": .string("nope")])
        }
        return false
      })
    })
    XCTAssertTrue(containsDenied, "Expected tool output denied in second request. Messages: \(secondRequest.messages)")

    // Finish stream 1.
    let c1 = await streams.continuation(at: 1)
    c1?.yield(.streamStart())
    c1?.yield(.startStep())
    c1?.yield(.finishStep(finishReason: .stop))
    c1?.yield(.finish(finishReason: .stop))
    c1?.finish()
  }

  func testSend_disconnectedStream_callsOnFinishWithPartialAssistantMessage_andLeavesStatusError() async throws {
    struct DisconnectedError: Error {}

    let ids = IDGenerator()
    let finishCapture = FinishCapture()
    let history = MessageHistory()

    let session = ChatSession(.init(
      id: "123",
      requestStream: { _, _, _, _, _, _ in
        AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          Task {
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.textStart(id: "text-1"))
            continuation.yield(.textDelta(id: "text-1", delta: "Hello"))
            continuation.finish(throwing: DisconnectedError())
          }
        }
      },
      onFinish: { event in await finishCapture.set(event) },
      generateID: { ids.nextID() }
    ))

    let updates = await session.updates(bufferingPolicy: .unbounded)
    let collectTask = Task {
      var lastMessages: [ChatMessage]? = nil
      for await snapshot in updates {
        if snapshot.status == .error { break }
        guard snapshot.messages != lastMessages else { continue }
        lastMessages = snapshot.messages
        await history.append(snapshot.messages)
      }
    }

    await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]))

    try await waitUntil { (await finishCapture.snapshot()) != nil }
    _ = await collectTask.value

    let maybeFinishEvent = await finishCapture.snapshot()
    let event = try XCTUnwrap(maybeFinishEvent)
    XCTAssertEqual(event.finishReason, nil)
    XCTAssertEqual(event.isAbort, false)
    XCTAssertEqual(event.isDisconnect, false)
    XCTAssertEqual(event.isError, true)

    XCTAssertEqual(event.messages, [
      .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
      .init(id: "id-1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "text-1", text: "Hello", state: .streaming)),
      ]),
    ])

    XCTAssertEqual(event.message, .init(id: "id-1", role: .assistant, parts: [
      .stepStart,
      .text(.init(id: "text-1", text: "Hello", state: .streaming)),
    ]))

    let status = await session.status
    XCTAssertEqual(status, .error)

    let historySnapshot = await history.snapshot()
    XCTAssertEqual(historySnapshot, [
      [],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
      ],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .text(.init(id: "text-1", text: "", state: .streaming)),
        ]),
      ],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .text(.init(id: "text-1", text: "Hello", state: .streaming)),
        ]),
      ],
    ])
  }

  func testSend_networkDisconnectedStream_setsIsDisconnectTrue_inOnFinish() async throws {
    let ids = IDGenerator()
    let finishCapture = FinishCapture()

    let session = ChatSession(.init(
      id: "123",
      requestStream: { _, _, _, _, _, _ in
        AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          Task {
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.textStart(id: "text-1"))
            continuation.yield(.textDelta(id: "text-1", delta: "Hello"))
            continuation.finish(throwing: URLError(.networkConnectionLost))
          }
        }
      },
      onFinish: { event in await finishCapture.set(event) },
      generateID: { ids.nextID() }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]))

    try await waitUntil { (await finishCapture.snapshot()) != nil }

    let maybeEvent = await finishCapture.snapshot()
    let event = try XCTUnwrap(maybeEvent)
    XCTAssertEqual(event.finishReason, nil)
    XCTAssertEqual(event.isAbort, false)
    XCTAssertEqual(event.isDisconnect, true)
    XCTAssertEqual(event.isError, true)

    let status = await session.status
    XCTAssertEqual(status, .error)
  }

  func testStop_abortsInFlightRequest_callsOnFinishWithPartialAssistantMessage_andReturnsToReady() async throws {
    let ids = IDGenerator()
    let finishCapture = FinishCapture()
    let termination = StreamTerminationCapture()
    let history = MessageHistory()

    let session = ChatSession(.init(
      id: "123",
      requestStream: { _, _, _, _, _, cancellationToken in
        AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          Task {
            await cancellationToken?.onCancel {
              Task { await termination.markCancelled() }
              continuation.yield(.abort)
              continuation.finish()
            }
          }

          Task {
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.textStart(id: "text-1"))
            continuation.yield(.textDelta(id: "text-1", delta: "Hello"))
          }
        }
      },
      onFinish: { event in await finishCapture.set(event) },
      // Asserts mid-stream partial-word visibility, which the funnel intentionally defers.
      generateID: { ids.nextID() },
      smoothing: .disabled
    ))

    let updates = await session.updates(bufferingPolicy: .unbounded)
    let collectTask = Task {
      var lastMessages: [ChatMessage]? = nil
      for await snapshot in updates {
        if (await finishCapture.snapshot()) != nil { break }
        guard snapshot.messages != lastMessages else { continue }
        lastMessages = snapshot.messages
        await history.append(snapshot.messages)
      }
    }

    let sendTask = Task {
      await session.send(.init(role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]))
    }
    defer {
      sendTask.cancel()
      collectTask.cancel()
    }

    try await waitUntil {
      let messages = await session.messages
      guard messages.count == 2, messages[1].role == .assistant else { return false }
      let assistantText = messages[1].parts.compactMap { part -> String? in
        guard case let .text(text) = part else { return nil }
        return text.text
      }.joined()
      return assistantText == "Hello"
    }

    await session.stop()

    try await waitUntil { (await finishCapture.snapshot()) != nil }
    try await waitUntil { (await session.status) == .ready }
    collectTask.cancel()

    let maybeFinishEvent = await finishCapture.snapshot()
    let event = try XCTUnwrap(maybeFinishEvent)
    XCTAssertEqual(event.finishReason, nil)
    XCTAssertEqual(event.isAbort, true)
    XCTAssertEqual(event.isDisconnect, false)
    XCTAssertEqual(event.isError, false)

    XCTAssertEqual(event.messages, [
      .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
      .init(id: "id-1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "text-1", text: "Hello", state: .streaming)),
      ]),
    ])

    XCTAssertEqual(event.message, .init(id: "id-1", role: .assistant, parts: [
      .stepStart,
      .text(.init(id: "text-1", text: "Hello", state: .streaming)),
    ]))

    let wasCancelled = await termination.snapshotWasCancelled()
    XCTAssertEqual(wasCancelled, true)

    let historySnapshot = await history.snapshot()
    XCTAssertEqual(historySnapshot, [
      [],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
      ],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .text(.init(id: "text-1", text: "", state: .streaming)),
        ]),
      ],
      [
        .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-text", text: "Hello, world!", state: .done))]),
        .init(id: "id-1", role: .assistant, parts: [
          .stepStart,
          .text(.init(id: "text-1", text: "Hello", state: .streaming)),
        ]),
      ],
    ])
  }

  func testSendReplaceUserMessage_replacesAndPrunesAndSubmitsWithMessageID() async throws {
    let ids = IDGenerator()
    let captured = RequestCapture()

    actor RequestIndex {
      private var value: Int = 0
      func next() -> Int {
        defer { value += 1 }
        return value
      }
    }

    let requestIndex = RequestIndex()

    let session = ChatSession(.init(
      id: "123",
      requestStream: { chatID, messages, trigger, messageID, options, _ in
        await captured.record(chatID: chatID, messages: messages, trigger: trigger, messageID: messageID, options: options)
        let idx = await requestIndex.next()

        return AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
          Task {
            let textID = "text-\(idx)"
            continuation.yield(.start())
            continuation.yield(.startStep)
            continuation.yield(.textStart(id: textID))
            continuation.yield(.textDelta(id: textID, delta: "ok"))
            continuation.yield(.textEnd(id: textID))
            continuation.yield(.finishStep)
            continuation.yield(.finish(finishReason: .stop))
            continuation.finish()
          }
        }
      },
      generateID: { ids.nextID() }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u-1", text: "One", state: .done))]))
    await session.send(.init(role: .user, parts: [.text(.init(id: "u-2", text: "Two", state: .done))]))
    await session.send(.init(
      role: .user,
      parts: [.text(.init(id: "u-1-edit", text: "ONE (edited)", state: .done))],
      replaceMessageID: "id-0"
    ))

    let snapshot = await session.snapshot()
    XCTAssertEqual(snapshot.messages, [
      .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-1-edit", text: "ONE (edited)", state: .done))]),
      .init(id: "id-4", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "text-2", text: "ok", state: .done)),
      ]),
    ])

    let maybeRequest = await captured.snapshot()
    let request = try XCTUnwrap(maybeRequest)
    XCTAssertEqual(request.chatID, "123")
    XCTAssertEqual(request.trigger, .submitMessage)
    XCTAssertEqual(request.messageID, "id-0")
    XCTAssertEqual(request.messages, [
      .init(id: "id-0", role: .user, parts: [.text(.init(id: "u-1-edit", text: "ONE (edited)", state: .done))]),
    ])
  }
}
