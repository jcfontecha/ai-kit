import Foundation
import AIKitProviders

public struct ChatSessionFinishEvent: Sendable {
  public var message: ChatMessage
  public var messages: [ChatMessage]
  public var isAbort: Bool
  public var isDisconnect: Bool
  public var isError: Bool
  public var finishReason: FinishReason?

  public init(
    message: ChatMessage,
    messages: [ChatMessage],
    isAbort: Bool,
    isDisconnect: Bool,
    isError: Bool,
    finishReason: FinishReason?
  ) {
    self.message = message
    self.messages = messages
    self.isAbort = isAbort
    self.isDisconnect = isDisconnect
    self.isError = isError
    self.finishReason = finishReason
  }
}

public struct ChatSessionInit: Sendable {
  public typealias ValidateJSONValue = @Sendable (_ value: JSONValue) async throws -> Void
  public typealias ReconnectToStream = @Sendable (
    _ chatID: String,
    _ options: ChatRequestOptions?
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error>?

  public typealias RequestStream = @Sendable (
    _ chatID: String,
    _ messages: [ChatMessage],
    _ trigger: ChatRequestTrigger,
    _ messageID: String?,
    _ options: ChatRequestOptions?,
    _ cancellationToken: CancellationToken?
  ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error>

  public var id: String?

  public var model: (any LanguageModel)?
  public var tools: ToolRegistry?
  public var toolChoice: ToolChoice
  public var activeTools: [String]?

  public var system: SystemPrompt?
  public var settings: CallSettings
  public var headers: [String: String]?
  public var providerOptions: ProviderOptions?

  public var onToolCall: (@Sendable (_ toolCall: ChatToolPart) async -> Void)?
  public var onData: (@Sendable (_ dataPart: AIUIMessageStreamDataPart) async -> Void)?
  public var sendAutomaticallyWhen: (@Sendable (_ messages: [ChatMessage]) async -> Bool)?

  /// Mirrors AI SDK `messageMetadataSchema` (`validateTypes`): validates message metadata chunks before merging.
  public var validateMessageMetadata: ValidateJSONValue?

  /// Mirrors AI SDK `dataPartSchemas` (`validateTypes`): keyed by full `data-*` type string.
  public var validateDataParts: [String: ValidateJSONValue]?

  public var requestStream: RequestStream?
  public var reconnectToStream: ReconnectToStream?

  public var onError: (@Sendable (_ error: Error) async -> Void)?
  public var onFinish: (@Sendable (_ event: ChatSessionFinishEvent) async -> Void)?

  public var generateID: (@Sendable () -> String)?

  public var messages: [ChatMessage]

  public init(
    id: String? = nil,
    model: (any LanguageModel)? = nil,
    tools: ToolRegistry? = nil,
    toolChoice: ToolChoice = .auto,
    activeTools: [String]? = nil,
    system: SystemPrompt? = nil,
    settings: CallSettings = .init(),
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    onToolCall: (@Sendable (_ toolCall: ChatToolPart) async -> Void)? = nil,
    onData: (@Sendable (_ dataPart: AIUIMessageStreamDataPart) async -> Void)? = nil,
    sendAutomaticallyWhen: (@Sendable (_ messages: [ChatMessage]) async -> Bool)? = nil,
    validateMessageMetadata: ValidateJSONValue? = nil,
    validateDataParts: [String: ValidateJSONValue]? = nil,
    requestStream: RequestStream? = nil,
    reconnectToStream: ReconnectToStream? = nil,
    onError: (@Sendable (_ error: Error) async -> Void)? = nil,
    onFinish: (@Sendable (_ event: ChatSessionFinishEvent) async -> Void)? = nil,
    generateID: (@Sendable () -> String)? = nil,
    messages: [ChatMessage] = []
  ) {
    self.id = id
    self.model = model
    self.tools = tools
    self.toolChoice = toolChoice
    self.activeTools = activeTools
    self.system = system
    self.settings = settings
    self.headers = headers
    self.providerOptions = providerOptions
    self.onToolCall = onToolCall
    self.onData = onData
    self.sendAutomaticallyWhen = sendAutomaticallyWhen
    self.validateMessageMetadata = validateMessageMetadata
    self.validateDataParts = validateDataParts
    self.requestStream = requestStream
    self.reconnectToStream = reconnectToStream
    self.onError = onError
    self.onFinish = onFinish
    self.generateID = generateID
    self.messages = messages
  }

  /// Convenience initializer for local chat driven by a configured `ToolLoopAgent`.
  ///
  /// This mirrors the AI SDK setup where the server decides whether responses come from
  /// `streamText(...)` directly or from an agent wrapper; here, the app makes that choice
  /// explicitly when running locally.
  public init<CALL_OPTIONS: Sendable>(
    id: String? = nil,
    agent: ToolLoopAgent<CALL_OPTIONS, Output.Text>,
    sendAutomaticallyWhen: (@Sendable (_ messages: [ChatMessage]) async -> Bool)? = nil,
    onError: (@Sendable (_ error: Error) async -> Void)? = nil,
    onFinish: (@Sendable (_ event: ChatSessionFinishEvent) async -> Void)? = nil,
    generateID: (@Sendable () -> String)? = nil,
    messages: [ChatMessage] = []
  ) {
    self.init(
      id: id,
      model: nil,
      tools: nil,
      toolChoice: .auto,
      activeTools: nil,
      system: nil,
      settings: .init(),
      headers: nil,
      providerOptions: nil,
      onToolCall: nil,
      onData: nil,
      sendAutomaticallyWhen: sendAutomaticallyWhen,
      validateMessageMetadata: nil,
      validateDataParts: nil,
      requestStream: { _, chatMessages, _, _, options, cancellationToken in
        let modelMessages = try await convertToModelMessages(
          chatMessages,
          options: .init(tools: nil, ignoreIncompleteToolCalls: false)
        )

        var configured = agent
        configured.headers = options?.headers
        configured.cancellationToken = cancellationToken

        let result = await configured.stream(messages: modelMessages, options: nil)
        return result.fullStream.flatMapToUIMessageStreamParts()
      },
      reconnectToStream: nil,
      onError: onError,
      onFinish: onFinish,
      generateID: generateID,
      messages: messages
    )
  }

  /// Convenience initializer for the “remote transport” mode where a server runs the AI SDK
  /// and iOS consumes the AI SDK UI message stream protocol (SSE v1).
  ///
  /// This mirrors AI SDK `useChat({ transport })` at the API level.
  public init(
    id: String? = nil,
    transport: some ChatTransport,
    tools: ToolRegistry? = nil,
    toolChoice: ToolChoice = .auto,
    activeTools: [String]? = nil,
    system: SystemPrompt? = nil,
    settings: CallSettings = .init(),
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    onToolCall: (@Sendable (_ toolCall: ChatToolPart) async -> Void)? = nil,
    onData: (@Sendable (_ dataPart: AIUIMessageStreamDataPart) async -> Void)? = nil,
    sendAutomaticallyWhen: (@Sendable (_ messages: [ChatMessage]) async -> Bool)? = nil,
    validateMessageMetadata: ValidateJSONValue? = nil,
    validateDataParts: [String: ValidateJSONValue]? = nil,
    onError: (@Sendable (_ error: Error) async -> Void)? = nil,
    onFinish: (@Sendable (_ event: ChatSessionFinishEvent) async -> Void)? = nil,
    generateID: (@Sendable () -> String)? = nil,
    messages: [ChatMessage] = []
  ) {
    self.init(
      id: id,
      model: nil,
      tools: tools,
      toolChoice: toolChoice,
      activeTools: activeTools,
      system: system,
      settings: settings,
      headers: headers,
      providerOptions: providerOptions,
      onToolCall: onToolCall,
      onData: onData,
      sendAutomaticallyWhen: sendAutomaticallyWhen,
      validateMessageMetadata: validateMessageMetadata,
      validateDataParts: validateDataParts,
      requestStream: transport.makeRequestStream(),
      reconnectToStream: transport.makeReconnectToStream(),
      onError: onError,
      onFinish: onFinish,
      generateID: generateID,
      messages: messages
    )
  }
}

public actor ChatSession {
  public nonisolated let id: String

  public private(set) var status: ChatSessionStatus
  public private(set) var error: Error?
  public private(set) var messages: [ChatMessage]

  private let broadcaster = ChatSessionUpdateBroadcaster()

  private var model: (any LanguageModel)?
  private var tools: ToolRegistry?
  private var toolChoice: ToolChoice
  private var activeTools: [String]?
  private var system: SystemPrompt?
  private var settings: CallSettings
  private var headers: [String: String]?
  private var providerOptions: ProviderOptions?
  private var onToolCall: (@Sendable (_ toolCall: ChatToolPart) async -> Void)?
  private var onData: (@Sendable (_ dataPart: AIUIMessageStreamDataPart) async -> Void)?
  private var sendAutomaticallyWhen: (@Sendable (_ messages: [ChatMessage]) async -> Bool)?
  private var validateMessageMetadata: ChatSessionInit.ValidateJSONValue?
  private var validateDataParts: [String: ChatSessionInit.ValidateJSONValue]?
  private var requestStream: ChatSessionInit.RequestStream?
  private var reconnectToStream: ChatSessionInit.ReconnectToStream?
  private var onError: (@Sendable (_ error: Error) async -> Void)?
  private var onFinish: (@Sendable (_ event: ChatSessionFinishEvent) async -> Void)?
  private var generateID: (@Sendable () -> String)?

  private var activeRequestTask: Task<Void, Never>?
  private var activeCancellationToken: CancellationToken?

  private func classifyDisconnect(_ error: Error) -> Bool {
    // Translation of AI SDK semantics:
    // `ai-sdk/packages/ai/src/ui/chat.ts` treats network-like errors as disconnect.
    // In Swift, we approximate this via URLError/NSURLErrorDomain.
    if let urlError = error as? URLError {
      switch urlError.code {
      case .networkConnectionLost,
           .timedOut,
           .cannotConnectToHost,
           .cannotFindHost,
           .dnsLookupFailed,
           .notConnectedToInternet,
           .internationalRoamingOff,
           .callIsActive,
           .dataNotAllowed,
           .secureConnectionFailed,
           .cannotLoadFromNetwork:
        return true
      default:
        return false
      }
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      return true
    }

    return false
  }

  public init(_ init: ChatSessionInit) {
    self.id = `init`.id ?? UUID().uuidString
    self.status = .ready
    self.error = nil
    self.messages = `init`.messages

    self.model = `init`.model
    self.tools = `init`.tools
    self.toolChoice = `init`.toolChoice
    self.activeTools = `init`.activeTools
    self.system = `init`.system
    self.settings = `init`.settings
    self.headers = `init`.headers
    self.providerOptions = `init`.providerOptions
    self.onToolCall = `init`.onToolCall
    self.onData = `init`.onData
    self.sendAutomaticallyWhen = `init`.sendAutomaticallyWhen
    self.validateMessageMetadata = `init`.validateMessageMetadata
    self.validateDataParts = `init`.validateDataParts
    self.requestStream = `init`.requestStream
    self.reconnectToStream = `init`.reconnectToStream
    self.onError = `init`.onError
    self.onFinish = `init`.onFinish
    self.generateID = `init`.generateID
  }

  private func validateStreamPart(_ part: AIUIMessageStreamPart) async throws {
    switch part {
    case .start(_, let messageMetadata):
      if let messageMetadata {
        try await validateMessageMetadata?(messageMetadata)
      }
    case .finish(_, let messageMetadata):
      if let messageMetadata {
        try await validateMessageMetadata?(messageMetadata)
      }
    case .messageMetadata(let messageMetadata):
      try await validateMessageMetadata?(messageMetadata)
    case .data(let dataPart):
      if let validator = validateDataParts?[dataPart.type] {
        try await validator(dataPart.data)
      }
    default:
      return
    }
  }

  public func snapshot() -> ChatSessionSnapshot {
    .init(status: status, messages: messages, errorDescription: error?.localizedDescription)
  }

  public func updates(
    bufferingPolicy: AsyncStream<ChatSessionSnapshot>.Continuation.BufferingPolicy = .bufferingNewest(1)
  ) async -> AsyncStream<ChatSessionSnapshot> {
    let initial = snapshot()
    return await broadcaster.makeStream(initial: initial, bufferingPolicy: bufferingPolicy)
  }

  public func send(_ message: ChatDraftMessage?, options: ChatRequestOptions? = nil) async {
    if let message {
      if let replaceID = message.replaceMessageID {
        guard let index = messages.firstIndex(where: { $0.id == replaceID }) else {
          await fail(AIKitError.invalidConfiguration("message with id \(replaceID) not found"))
          return
        }
        guard messages[index].role == .user else {
          await fail(AIKitError.invalidConfiguration("message with id \(replaceID) is not a user message"))
          return
        }
        messages = Array(messages.prefix(index + 1))
        messages[index] = .init(id: replaceID, role: message.role, parts: message.parts, metadata: message.metadata)
      } else {
        messages.append(.init(id: nextID(), role: message.role, parts: message.parts, metadata: message.metadata))
      }
    }

    await emitUpdate()
    await submit(trigger: .submitMessage, messageID: message?.replaceMessageID, options: options)
  }

  public func submit(options: ChatRequestOptions? = nil) async {
    await submit(trigger: .submitMessage, messageID: messages.last?.id, options: options)
  }

  public func regenerate(messageID: String? = nil, options: ChatRequestOptions? = nil) async {
    let targetIndex: Int?
    if let messageID {
      targetIndex = messages.firstIndex(where: { $0.id == messageID })
      if targetIndex == nil {
        await fail(AIKitError.invalidConfiguration("message \(messageID) not found"))
        return
      }
    } else {
      targetIndex = messages.isEmpty ? nil : messages.count - 1
    }

    guard let messageIndex = targetIndex else {
      await submit(options: options)
      return
    }

    let message = messages[messageIndex]
    let cutIndex = (message.role == .assistant) ? messageIndex : (messageIndex + 1)
    messages = Array(messages.prefix(cutIndex))
    await emitUpdate()

    await submit(trigger: .regenerateMessage, messageID: messageID, options: options)
  }

  public func resumeStream(options: ChatRequestOptions? = nil) async {
    guard status != .submitted && status != .streaming else { return }
    clearError()

    guard reconnectToStream != nil else {
      await fail(AIKitError.notImplemented("resumeStream requires a `ChatSessionInit.reconnectToStream` implementation."))
      return
    }

    status = .submitted
    await emitUpdate()

    let task = Task { [weak self] in
      guard let self else { return }
      await self.runResumeStream(options: options)
    }

    activeRequestTask = task
    await task.value
  }

  public func setMessages(_ update: @Sendable ([ChatMessage]) -> [ChatMessage]) {
    self.messages = update(self.messages)
    Task { [weak self] in await self?.emitUpdate() }
  }

  public func addToolOutput<I: Codable & Sendable, O: Codable & Sendable>(
    tool: ToolID<I, O>,
    toolCallID: String,
    output: O
  ) async {
    do {
      let jsonValue = try encodeJSONValue(output)
      updateToolPart(toolCallID: toolCallID) { toolPart in
        toolPart.output = jsonValue
        toolPart.state = .outputAvailable(preliminary: false)
      }
      await maybeAutoSubmit()
    } catch {
      self.error = error
      self.status = .error
      await onError?(error)
    }
  }

  public func addToolOutputError<I: Codable & Sendable, O: Codable & Sendable>(
    tool: ToolID<I, O>,
    toolCallID: String,
    errorText: String
  ) async {
    updateToolPart(toolCallID: toolCallID) { toolPart in
      toolPart.state = .outputError(errorText: errorText)
    }
    await maybeAutoSubmit()
  }

  public func addToolApprovalResponse(
    approvalID: String,
    approved: Bool,
    reason: String? = nil
  ) async {
    updateToolPart(matchingApprovalID: approvalID) { toolPart in
      toolPart.state = .approvalResponded(approvalID: approvalID, approved: approved, reason: reason)
      toolPart.approval = .init(id: approvalID, approved: approved, reason: reason)
    }
    await maybeAutoSubmit()
  }

  public func stop() async {
    guard status == .submitted || status == .streaming else { return }
    await activeCancellationToken?.cancel()
    activeRequestTask?.cancel()
    // Status update is handled when the request observes cancellation, but we still emit a best-effort update.
    await emitUpdate()
  }

  public func clearError() {
    if status == .error {
      error = nil
      status = .ready
      Task { [weak self] in await self?.emitUpdate() }
    }
  }

  private func emitUpdate() async {
    let snap = snapshot()
    await broadcaster.broadcast(snap)
  }

  private func maybeAutoSubmit() async {
    guard status != .submitted && status != .streaming else { return }
    guard let predicate = sendAutomaticallyWhen else { return }
    let shouldSubmit = await predicate(messages)
    guard shouldSubmit else { return }
    Task { [weak self] in
      await self?.submit(options: nil)
    }
  }

  private func updateToolPart(
    toolCallID: String,
    update: (inout ChatToolPart) -> Void
  ) {
    guard let lastAssistantIndex = messages.lastIndex(where: { $0.role == .assistant }) else { return }
    guard let toolPartIndex = messages[lastAssistantIndex].parts.lastIndex(where: { part in
      guard case let .tool(tool) = part else { return false }
      return tool.toolCallID == toolCallID
    }) else { return }
    guard case var .tool(toolPart) = messages[lastAssistantIndex].parts[toolPartIndex] else { return }
    update(&toolPart)
    messages[lastAssistantIndex].parts[toolPartIndex] = .tool(toolPart)
  }

  private func updateToolPart(
    matchingApprovalID approvalID: String,
    update: (inout ChatToolPart) -> Void
  ) {
    guard let lastAssistantIndex = messages.lastIndex(where: { $0.role == .assistant }) else { return }
    guard let toolPartIndex = messages[lastAssistantIndex].parts.lastIndex(where: { part in
      guard case let .tool(tool) = part else { return false }
      if tool.approval?.id == approvalID { return true }
      if case let .approvalRequested(existingID) = tool.state {
        return existingID == approvalID
      }
      return false
    }) else { return }
    guard case var .tool(toolPart) = messages[lastAssistantIndex].parts[toolPartIndex] else { return }
    update(&toolPart)
    messages[lastAssistantIndex].parts[toolPartIndex] = .tool(toolPart)
  }

  private func encodeJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    if let json = JSONValue.from(object) {
      return json
    }
    return .null
  }

  private func setNotImplemented(_ name: String) async {
    let error = AIKitError.notImplemented("\(name) is not implemented yet.")
    await fail(error)
  }

  private func fail(_ error: Error) async {
    self.error = error
    self.status = .error
    await emitUpdate()
    await onError?(error)
  }

  private func nextID() -> String {
    generateID?() ?? UUID().uuidString
  }

  private func submit(
    trigger: ChatRequestTrigger,
    messageID: String?,
    options: ChatRequestOptions?
  ) async {
    guard status != .submitted && status != .streaming else { return }
    clearError()

    let headers = options?.headers ?? self.headers

    status = .submitted
    await emitUpdate()

    let task = Task { [weak self] in
      guard let self else { return }
      await self.runRequest(trigger: trigger, messageID: messageID, options: options, headers: headers)
    }

    activeRequestTask = task
    await task.value
  }

  private func runRequest(
    trigger: ChatRequestTrigger,
    messageID: String?,
    options: ChatRequestOptions?,
    headers: [String: String]?
  ) async {
    var isAbort = false
    var isDisconnect = false
    var isError = false
    var finishReason: FinishReason?
    var reducerState = ChatMessageStreamingReducer.State()

    // For now, only operate on a snapshot of messages at submission time.
    // This matches the AI SDK behavior: state can still be edited, but the in-flight request uses the snapshot.
    let inputMessages = messages

    do {
      let cancellationToken = CancellationToken()
      activeCancellationToken = cancellationToken

      let stream: AsyncThrowingStream<AIUIMessageStreamPart, Error>
      if let requestStream {
        let effectiveOptions = ChatRequestOptions(headers: headers, body: options?.body, metadata: options?.metadata)
        stream = try await requestStream(id, inputMessages, trigger, messageID, effectiveOptions, cancellationToken)
      } else {
        guard let model else {
          throw AIKitError.invalidConfiguration("ChatSession requires `model` unless `requestStream` is provided.")
        }

        let modelMessages = try await convertToModelMessages(
          inputMessages,
          options: .init(tools: tools, ignoreIncompleteToolCalls: false)
        )

        let result = streamText(.init(
          model: model,
          system: system,
          prompt: nil,
          messages: modelMessages,
          tools: tools,
          toolChoice: toolChoice,
          activeTools: activeTools,
          settings: settings,
          headers: headers,
          providerOptions: providerOptions,
          maxRetries: 0,
          cancellationToken: activeCancellationToken,
          prepareStep: nil,
          repairToolCall: nil,
          download: nil,
          includeRawParts: false,
          transform: nil,
          stopWhen: [Stop.stepCountIs(1)],
          output: Output.Text()
        ))

        stream = result.fullStream
          .flatMapToUIMessageStreamParts()
      }

      for try await part in stream {
        if case .abort = part {
          isAbort = true
          break
        }

        if Task.isCancelled {
          isAbort = true
          break
        }

        try await validateStreamPart(part)

        if case .finish(let reason, _) = part {
          finishReason = reason
        }

        switch part {
        case .error(let message):
          isError = true
          await fail(AIKitError.invalidConfiguration(message))
          break

        case .data(let dataChunk) where dataChunk.transient == true:
          await onData?(dataChunk)
          break

        case .start, .finish, .messageMetadata,
             .textStart, .textDelta, .textEnd,
             .reasoningStart, .reasoningDelta, .reasoningEnd,
             .file, .sourceURL, .sourceDocument,
             .toolInputStart, .toolInputDelta, .toolInputEnd,
             .toolInputAvailable, .toolInputError,
             .toolOutputAvailable, .toolOutputError, .toolOutputDenied,
             .toolApprovalRequest,
             .data,
             .startStep, .finishStep:
          if status == .submitted {
            status = .streaming
            await emitUpdate()
          }
          ChatMessageStreamingReducer.apply(part, messages: &messages, state: &reducerState, makeMessageID: nextID)

          if case .data(let dataChunk) = part {
            await onData?(dataChunk)
          }

          await emitUpdate()

          if case .toolInputAvailable(let call) = part,
             call.providerExecuted != true,
             let tool = latestToolPart(toolCallID: call.toolCallID) {
            await onToolCall?(tool)
          }

        default:
          break
        }

        if isError {
          break
        }
      }

      if isAbort {
        status = .ready
      } else if isError == false {
        status = .ready
      }
      await emitUpdate()
    } catch is CancellationError {
      isAbort = true
      status = .ready
      await emitUpdate()
    } catch {
      isError = true
      isDisconnect = classifyDisconnect(error)
      await fail(error)
    }

    activeRequestTask = nil
    activeCancellationToken = nil

    if let lastAssistant = messages.last(where: { $0.role == .assistant }) {
      await onFinish?(.init(
        message: lastAssistant,
        messages: messages,
        isAbort: isAbort,
        isDisconnect: isDisconnect,
        isError: isError,
        finishReason: finishReason
      ))
    }

    if isError == false && isAbort == false {
      await maybeAutoSubmit()
    }
  }

  private func runResumeStream(options: ChatRequestOptions?) async {
    var isAbort = false
    var isDisconnect = false
    var isError = false
    var finishReason: FinishReason?
    var reducerState = ChatMessageStreamingReducer.State()

    do {
      let stream = try await reconnectToStream?(id, options)

      // No active stream found; nothing to resume.
      if stream == nil {
        status = .ready
        await emitUpdate()
        return
      }

      for try await part in stream! {
        if case .abort = part {
          isAbort = true
          break
        }

        if Task.isCancelled {
          isAbort = true
          break
        }

        try await validateStreamPart(part)

        if case .finish(let reason, _) = part {
          finishReason = reason
        }

        switch part {
        case .error(let message):
          isError = true
          await fail(AIKitError.invalidConfiguration(message))
          break

        case .data(let dataChunk) where dataChunk.transient == true:
          await onData?(dataChunk)
          break

        case .start, .finish, .messageMetadata,
             .textStart, .textDelta, .textEnd,
             .reasoningStart, .reasoningDelta, .reasoningEnd,
             .file, .sourceURL, .sourceDocument,
             .toolInputStart, .toolInputDelta, .toolInputEnd,
             .toolInputAvailable, .toolInputError,
             .toolOutputAvailable, .toolOutputError, .toolOutputDenied,
             .toolApprovalRequest,
             .data,
             .startStep, .finishStep:
          if status == .submitted {
            status = .streaming
            await emitUpdate()
          }
          ChatMessageStreamingReducer.apply(part, messages: &messages, state: &reducerState, makeMessageID: nextID)

          if case .data(let dataChunk) = part {
            await onData?(dataChunk)
          }

          await emitUpdate()

          if case .toolInputAvailable(let call) = part,
             call.providerExecuted != true,
             let tool = latestToolPart(toolCallID: call.toolCallID) {
            await onToolCall?(tool)
          }

        default:
          break
        }

        if isError {
          break
        }
      }

      if isAbort {
        status = .ready
      } else if isError == false {
        status = .ready
      }
      await emitUpdate()
    } catch is CancellationError {
      isAbort = true
      status = .ready
      await emitUpdate()
    } catch {
      isError = true
      isDisconnect = classifyDisconnect(error)
      await fail(error)
    }

    activeRequestTask = nil
    activeCancellationToken = nil

    if let lastAssistant = messages.last(where: { $0.role == .assistant }) {
      await onFinish?(.init(
        message: lastAssistant,
        messages: messages,
        isAbort: isAbort,
        isDisconnect: isDisconnect,
        isError: isError,
        finishReason: finishReason
      ))
    }

    if isError == false && isAbort == false {
      await maybeAutoSubmit()
    }
  }

  private func latestToolPart(toolCallID: String) -> ChatToolPart? {
    guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return nil }
    for part in lastAssistant.parts.reversed() {
      guard case let .tool(tool) = part else { continue }
      if tool.toolCallID == toolCallID { return tool }
    }
    return nil
  }
}
