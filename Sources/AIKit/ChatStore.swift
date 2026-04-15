#if canImport(Combine)
import Combine
import Foundation
import AIKitProviders

@MainActor
public final class ChatStore: ObservableObject {
  public struct RemoteConfiguration {
    public typealias ValidateJSONValue = @Sendable (_ value: JSONValue) async throws -> Void

    public var id: String?
    public var initialMessages: [ChatMessage]

    /// Optional async header provider, evaluated for each request (including auto-resubmits).
    public var headers: (@Sendable () async throws -> [String: String])?

    /// Optional async body provider, evaluated for each request (including auto-resubmits).
    public var body: (@Sendable () async throws -> JSONValue?)?

    /// Called when the server emits a tool call that is not provider-executed.
    public var onToolCall: (@Sendable (_ toolCall: ChatToolPart) async -> Void)?

    /// Receives non-transient `data-*` parts emitted by the server.
    public var onData: (@Sendable (_ dataPart: AIUIMessageStreamDataPart) async -> Void)?

    public var validateMessageMetadata: ValidateJSONValue?
    public var validateDataParts: [String: ValidateJSONValue]?

    public init(
      id: String? = nil,
      initialMessages: [ChatMessage] = [],
      headers: (@Sendable () async throws -> [String: String])? = nil,
      body: (@Sendable () async throws -> JSONValue?)? = nil,
      onToolCall: (@Sendable (_ toolCall: ChatToolPart) async -> Void)? = nil,
      onData: (@Sendable (_ dataPart: AIUIMessageStreamDataPart) async -> Void)? = nil,
      validateMessageMetadata: ValidateJSONValue? = nil,
      validateDataParts: [String: ValidateJSONValue]? = nil
    ) {
      self.id = id
      self.initialMessages = initialMessages
      self.headers = headers
      self.body = body
      self.onToolCall = onToolCall
      self.onData = onData
      self.validateMessageMetadata = validateMessageMetadata
      self.validateDataParts = validateDataParts
    }
  }

  @Published public var messages: [ChatMessage]
  @Published public var input: String
  @Published public var status: ChatStatus
  @Published public var errorDescription: String?

  public var isLoading: Bool { status == .submitted || status == .streaming }

  public var defaultRequestOptions: ChatRequestOptions

  private let session: ChatSession
  private var updatesTask: Task<Void, Never>?

  public init(
    remote url: URL,
    configuration: RemoteConfiguration = .init(),
    requestOptions: ChatRequestOptions = .init(),
    sendAutomaticallyWhen: (@Sendable ([ChatMessage]) async -> Bool)? = { messages in
      ChatAutoSubmitPredicates
        .lastAssistantMessageIsCompleteWithToolCallsOrApprovalResponses(messages: messages)
    }
  ) {
    self.defaultRequestOptions = requestOptions
    self.messages = []
    self.input = ""
    self.status = .ready
    self.errorDescription = nil

    let transport = AIUIChatEndpointTransport(
      url: url,
      httpTransport: URLSessionHTTPTransport(),
      headers: configuration.headers,
      body: configuration.body,
      encoder: AIUIMessageEncoder()
    )
    self.session = ChatSession(.init(
      id: configuration.id,
      transport: transport,
      onToolCall: configuration.onToolCall,
      onData: configuration.onData,
      sendAutomaticallyWhen: sendAutomaticallyWhen,
      validateMessageMetadata: configuration.validateMessageMetadata,
      validateDataParts: configuration.validateDataParts,
      messages: configuration.initialMessages
    ))

    startUpdatesTask()
  }

  /// Local, streamText-powered chat.
  public init(
    model: any LanguageModel,
    system: SystemPrompt? = nil,
    tools: ToolRegistry? = nil,
    toolChoice: ToolChoice = .auto,
    activeTools: [String]? = nil,
    settings: CallSettings = .init(),
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    convertDataPart: ChatDataPartConverter? = nil,
    initialMessages: [ChatMessage] = [],
    sendAutomaticallyWhen: (@Sendable ([ChatMessage]) async -> Bool)? = { messages in
      ChatAutoSubmitPredicates
        .lastAssistantMessageIsCompleteWithToolCallsOrApprovalResponses(messages: messages)
    }
  ) {
    self.defaultRequestOptions = .init()
    self.messages = initialMessages
    self.input = ""
    self.status = .ready
    self.errorDescription = nil

    self.session = ChatSession(.init(
      model: model,
      tools: tools,
      toolChoice: toolChoice,
      activeTools: activeTools,
      system: system,
      settings: settings,
      headers: headers,
      providerOptions: providerOptions,
      sendAutomaticallyWhen: sendAutomaticallyWhen,
      convertDataPart: convertDataPart,
      messages: initialMessages
    ))

    startUpdatesTask()
  }

  /// Local, agent-powered chat. The agent owns loop policy (`stopWhen`, `prepareCall`, etc.).
  @_spi(Advanced)
  public init<CALL_OPTIONS: Sendable>(
    agent: Agent<CALL_OPTIONS, Output.Text>,
    convertDataPart: ChatDataPartConverter? = nil,
    sendAutomaticallyWhen: (@Sendable ([ChatMessage]) async -> Bool)? = { messages in
      ChatAutoSubmitPredicates
        .lastAssistantMessageIsCompleteWithToolCallsOrApprovalResponses(messages: messages)
    }
  ) {
    self.defaultRequestOptions = .init()
    self.messages = []
    self.input = ""
    self.status = .ready
    self.errorDescription = nil

    self.session = ChatSession(.init(agent: agent, sendAutomaticallyWhen: sendAutomaticallyWhen, convertDataPart: convertDataPart))

    startUpdatesTask()
  }

  deinit {
    updatesTask?.cancel()
  }

  public func sendMessage(_ text: String? = nil, options: ChatRequestOptions? = nil) {
    sendMessage(text, files: [], options: options)
  }

  public func sendMessage(
    _ text: String? = nil,
    files: [ChatFilePart],
    dataParts: [ChatDataPart] = [],
    metadata: JSONValue? = nil,
    options: ChatRequestOptions? = nil
  ) {
    let resolvedText = text ?? input
    guard resolvedText.isEmpty == false || files.isEmpty == false || dataParts.isEmpty == false else { return }
    input = ""

    var parts: [ChatMessagePart] = []
    if resolvedText.isEmpty == false {
      parts.append(.text(.init(id: UUID().uuidString, text: resolvedText, state: .done)))
    }
    parts.append(contentsOf: files.map { .file($0) })
    parts.append(contentsOf: dataParts.map { .data($0) })

    let merged = merge(defaultRequestOptions, options)
    Task { [session] in
      let message = ChatDraftMessage(role: .user, parts: parts, metadata: metadata)
      await session.send(message, options: merged)
    }
  }

  public func replaceUserMessage(messageID: String, text: String? = nil, options: ChatRequestOptions? = nil) {
    replaceUserMessage(messageID: messageID, text: text, files: [], options: options)
  }

  public func replaceUserMessage(
    messageID: String,
    text: String? = nil,
    files: [ChatFilePart],
    dataParts: [ChatDataPart] = [],
    options: ChatRequestOptions? = nil
  ) {
    let resolvedText = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
    guard resolvedText.isEmpty == false || files.isEmpty == false || dataParts.isEmpty == false else { return }
    input = ""

    var parts: [ChatMessagePart] = []
    if resolvedText.isEmpty == false {
      parts.append(.text(.init(id: UUID().uuidString, text: resolvedText, state: .done)))
    }
    parts.append(contentsOf: files.map { .file($0) })
    parts.append(contentsOf: dataParts.map { .data($0) })

    let merged = merge(defaultRequestOptions, options)
    Task { [session] in
      let message = ChatDraftMessage(role: .user, parts: parts, replaceMessageID: messageID)
      await session.send(message, options: merged)
    }
  }

  public func regenerate(messageID: String? = nil, options: ChatRequestOptions? = nil) {
    let merged = merge(defaultRequestOptions, options)
    Task { [session] in
      await session.regenerate(messageID: messageID, options: merged)
    }
  }

  public func stop() {
    Task { [session] in
      await session.stop()
    }
  }

  public func resume(options: ChatRequestOptions? = nil) {
    let merged = merge(defaultRequestOptions, options)
    Task { [session] in
      await session.resumeStream(options: merged)
    }
  }

  public func addToolOutput(to tool: ChatToolPart, output: JSONValue) {
    Task { [session] in
      await session.addToolOutput(
        tool: ToolID<JSONValue, JSONValue>(tool.toolName),
        toolCallID: tool.toolCallID,
        output: output
      )
    }
  }

  public func addToolOutput(toolName: String, toolCallID: String, output: JSONValue) {
    Task { [session] in
      await session.addToolOutput(
        tool: ToolID<JSONValue, JSONValue>(toolName),
        toolCallID: toolCallID,
        output: output
      )
    }
  }

  public func addToolApprovalResponse(approvalID: String, approved: Bool, reason: String? = nil) {
    Task { [session] in
      await session.addToolApprovalResponse(approvalID: approvalID, approved: approved, reason: reason)
    }
  }

  private func startUpdatesTask() {
    let session = self.session
    updatesTask = Task { [weak self] in
      guard let self else { return }
      let initial = await session.snapshot()
      await MainActor.run {
        self.applySnapshot(initial)
      }
      let updates = await session.updates(bufferingPolicy: .bufferingNewest(1))
      for await snap in updates {
        await MainActor.run {
          self.applySnapshot(snap)
        }
      }
    }
  }

  private func applySnapshot(_ snapshot: ChatSessionSnapshot) {
    status = snapshot.status
    messages = snapshot.messages
    errorDescription = snapshot.errorDescription
  }

  private func merge(_ base: ChatRequestOptions, _ override: ChatRequestOptions?) -> ChatRequestOptions? {
    guard let override else {
      return base == .init() ? nil : base
    }

    let headers = override.headers ?? base.headers
    let body = override.body ?? base.body
    let metadata = override.metadata ?? base.metadata

    let merged = ChatRequestOptions(headers: headers, body: body, metadata: metadata)
    return merged == .init() ? nil : merged
  }
}
#endif
