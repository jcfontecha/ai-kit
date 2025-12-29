import Foundation
import AIKitProviders

private struct UnsafeSendable<Value>: @unchecked Sendable {
  let value: Value
}

private final class Locked<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) {
    self.value = value
  }

  func withLock<T>(_ body: (inout Value) -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body(&value)
  }

  func get() -> Value {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

public enum TextStreamPart: Sendable, Equatable {
  case start
  case finish(finishReason: FinishReason, rawFinishReason: String? = nil, totalUsage: Usage = .init())
  case abort

  case startStep(request: LanguageModelRequestMetadata = .init(), warnings: [CallWarning] = [])
  case finishStep(
    response: LanguageModelResponseMetadata = .init(),
    usage: Usage = .init(),
    finishReason: FinishReason,
    rawFinishReason: String? = nil,
    providerMetadata: ProviderMetadata? = nil
  )

  case textStart(id: String, providerMetadata: ProviderMetadata? = nil)
  case textDelta(id: String, text: String, providerMetadata: ProviderMetadata? = nil)
  case textEnd(id: String, providerMetadata: ProviderMetadata? = nil)

  case reasoningStart(id: String, providerMetadata: ProviderMetadata? = nil)
  case reasoningDelta(id: String, text: String, providerMetadata: ProviderMetadata? = nil)
  case reasoningEnd(id: String, providerMetadata: ProviderMetadata? = nil)

  case toolInputStart(
    id: String,
    toolName: String,
    providerMetadata: ProviderMetadata? = nil,
    providerExecuted: Bool? = nil,
    dynamic: Bool? = nil,
    title: String? = nil
  )
  case toolInputDelta(id: String, delta: String, providerMetadata: ProviderMetadata? = nil)
  case toolInputEnd(id: String, providerMetadata: ProviderMetadata? = nil)

  case source(Source)
  case file(GeneratedFile)

  case toolCall(ToolCall)
  case toolResult(ToolResult)
  case toolError(ToolError)
  case toolOutputDenied(ToolOutputDenied)
  case toolApprovalRequest(ToolApprovalRequest)
  case toolApprovalResponse(ToolApprovalResponse)

  case raw(JSONValue)
  case error(String)
}

public struct StreamTextOptions<OUT: OutputSpec>: Sendable {
  public var model: any LanguageModel

  public var system: SystemPrompt?
  public var prompt: String?
  public var messages: [ModelMessage]?

  public var tools: ToolRegistry?
  public var toolChoice: ToolChoice
  public var activeTools: [String]?

  public var settings: CallSettings
  public var headers: [String: String]?
  public var providerOptions: ProviderOptions?
  public var maxRetries: Int
  public var cancellationToken: CancellationToken?
  public var prepareStep: PrepareStepFunction?
  public var repairToolCall: ToolCallRepairFunction?
  public var download: DownloadFunction?
  public var includeRawParts: Bool
  public var transform: StreamTextTransform?

  public var stopWhen: [StopCondition]
  public var output: OUT

  public var experimentalContext: AnySendable?

  public var onChunk: (@Sendable (TextStreamPart) async -> Void)?
  public var onError: (@Sendable (_ error: String) async -> Void)?
  public var onAbort: (@Sendable () async -> Void)?
  public var onStepFinish: (@Sendable (StepResult) async -> Void)?
  public var onFinish: (@Sendable (StreamTextFinishEvent<OUT>) async -> Void)?

  public init(
    model: any LanguageModel,
    system: SystemPrompt? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    tools: ToolRegistry? = nil,
    toolChoice: ToolChoice = .auto,
    activeTools: [String]? = nil,
    settings: CallSettings = .init(),
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int = 2,
    cancellationToken: CancellationToken? = nil,
    prepareStep: PrepareStepFunction? = nil,
    repairToolCall: ToolCallRepairFunction? = nil,
    download: DownloadFunction? = nil,
    includeRawParts: Bool = false,
    transform: StreamTextTransform? = nil,
    stopWhen: [StopCondition] = [Stop.stepCountIs(1)],
    output: OUT,
    experimentalContext: AnySendable? = nil,
    onChunk: (@Sendable (TextStreamPart) async -> Void)? = nil,
    onError: (@Sendable (_ error: String) async -> Void)? = nil,
    onAbort: (@Sendable () async -> Void)? = nil,
    onStepFinish: (@Sendable (StepResult) async -> Void)? = nil,
    onFinish: (@Sendable (StreamTextFinishEvent<OUT>) async -> Void)? = nil
  ) {
    self.model = model
    self.system = system
    self.prompt = prompt
    self.messages = messages
    self.tools = tools
    self.toolChoice = toolChoice
    self.activeTools = activeTools
    self.settings = settings
    self.headers = headers
    self.providerOptions = providerOptions
    self.maxRetries = maxRetries
    self.cancellationToken = cancellationToken
    self.prepareStep = prepareStep
    self.repairToolCall = repairToolCall
    self.download = download
    self.includeRawParts = includeRawParts
    self.transform = transform
    self.stopWhen = stopWhen
    self.output = output
    self.experimentalContext = experimentalContext
    self.onChunk = onChunk
    self.onError = onError
    self.onAbort = onAbort
    self.onStepFinish = onStepFinish
    self.onFinish = onFinish
  }
}

public typealias StreamTextTransform = @Sendable (
  _ input: AsyncThrowingStream<TextStreamPart, Error>
) -> AsyncThrowingStream<TextStreamPart, Error>

public struct StreamTextFinishEvent<OUT: OutputSpec>: Sendable {
  public var steps: [StepResult]
  public var totalUsage: Usage
  public var finishReason: FinishReason
  public var rawFinishReason: String?
  public var providerMetadata: ProviderMetadata?
  public var experimentalContext: AnySendable?
  public var output: OUT.Complete?

  public init(
    steps: [StepResult],
    totalUsage: Usage,
    finishReason: FinishReason,
    rawFinishReason: String? = nil,
    providerMetadata: ProviderMetadata? = nil,
    experimentalContext: AnySendable? = nil,
    output: OUT.Complete? = nil
  ) {
    self.steps = steps
    self.totalUsage = totalUsage
    self.finishReason = finishReason
    self.rawFinishReason = rawFinishReason
    self.providerMetadata = providerMetadata
    self.experimentalContext = experimentalContext
    self.output = output
  }
}

public struct StreamTextResult<OUT: OutputSpec>: Sendable {
  public var textStream: AsyncThrowingStream<String, Error>
  public var fullStream: AsyncThrowingStream<TextStreamPart, Error>
  public var partialOutputStream: AsyncThrowingStream<OUT.Partial, Error>
  private let collector: StreamTextCollector<OUT>

  fileprivate init(
    textStream: AsyncThrowingStream<String, Error>,
    fullStream: AsyncThrowingStream<TextStreamPart, Error>,
    partialOutputStream: AsyncThrowingStream<OUT.Partial, Error>,
    collector: StreamTextCollector<OUT>
  ) {
    self.textStream = textStream
    self.fullStream = fullStream
    self.partialOutputStream = partialOutputStream
    self.collector = collector
  }

  public var content: [ContentPart] {
    get async throws {
      let result = try await collector.value()
      return result.steps.last?.content ?? []
    }
  }

  public var output: OUT.Complete {
    get async throws {
      let result = try await collector.value()
      if let error = result.outputError { throw error }
      if let outputValue = result.outputValue { return outputValue }
      throw AIKitError.invalidConfiguration("No output generated.")
    }
  }

  public var text: String {
    get async throws {
      let result = try await collector.value()
      return result.steps.last?.text ?? ""
    }
  }

  public var reasoning: [ReasoningOutput] {
    get async throws {
      let result = try await collector.value()
      let content = result.steps.last?.content ?? []
      return content.compactMap { part in
        if case let .reasoning(text, metadata) = part {
          return .init(text: text, providerMetadata: metadata)
        }
        return nil
      }
    }
  }

  public var reasoningText: String? {
    get async throws {
      let combined = try await reasoning.map(\.text).joined()
      return combined.isEmpty ? nil : combined
    }
  }

  public var files: [GeneratedFile] {
    get async throws {
      let result = try await collector.value()
      let content = result.steps.last?.content ?? []
      return content.compactMap { part in
        if case let .file(file) = part { return file }
        return nil
      }
    }
  }

  public var sources: [Source] {
    get async throws {
      let result = try await collector.value()
      let content = result.steps.last?.content ?? []
      return content.compactMap { part in
        if case let .source(source) = part { return source }
        return nil
      }
    }
  }

  public var toolCalls: [ToolCall] {
    get async throws {
      let result = try await collector.value()
      return result.steps.last?.toolCalls ?? []
    }
  }

  public var toolResults: [ToolResult] {
    get async throws {
      let result = try await collector.value()
      return result.steps.last?.toolResults ?? []
    }
  }

  public var usage: Usage {
    get async throws {
      let result = try await collector.value()
      return result.steps.last?.usage ?? .init()
    }
  }

  public var steps: [StepResult] {
    get async throws {
      let result = try await collector.value()
      return result.steps
    }
  }

  public var totalUsage: Usage {
    get async throws {
      let result = try await collector.value()
      return result.totalUsage
    }
  }

  public var warnings: [CallWarning]? {
    get async throws {
      let result = try await collector.value()
      return result.steps.first?.warnings
    }
  }

  public var request: LanguageModelRequestMetadata {
    get async throws {
      let result = try await collector.value()
      return result.steps.last?.request ?? .init()
    }
  }

  public var response: LanguageModelResponseMetadata {
    get async throws {
      let result = try await collector.value()
      return result.steps.last?.response ?? .init()
    }
  }

  public var providerMetadata: ProviderMetadata? {
    get async throws {
      let result = try await collector.value()
      return result.steps.last?.providerMetadata
    }
  }

  public var responseMessages: [ModelMessage] {
    get async throws {
      let result = try await collector.value()
      return result.steps.last?.responseMessages ?? []
    }
  }

  public var finishReason: FinishReason {
    get async throws {
      let result = try await collector.value()
      return result.finishReason
    }
  }

  public var rawFinishReason: String? {
    get async throws {
      let result = try await collector.value()
      return result.rawFinishReason
    }
  }

  public func consumeStream() async throws {
    for try await _ in fullStream {}
  }
}

private struct StreamTextFinalResult<OUT: OutputSpec>: Sendable {
  var steps: [StepResult]
  var totalUsage: Usage
  var finishReason: FinishReason
  var rawFinishReason: String?
  var outputValue: OUT.Complete?
  var outputError: Error?
}

private actor StreamTextCollector<OUT: OutputSpec> {
  private var result: Result<StreamTextFinalResult<OUT>, Error>?
  private var continuations: [CheckedContinuation<StreamTextFinalResult<OUT>, Error>] = []

  func resolve(_ value: StreamTextFinalResult<OUT>) {
    guard result == nil else { return }
    result = .success(value)
    for continuation in continuations {
      continuation.resume(returning: value)
    }
    continuations.removeAll()
  }

  func reject(_ error: Error) {
    guard result == nil else { return }
    result = .failure(error)
    for continuation in continuations {
      continuation.resume(throwing: error)
    }
    continuations.removeAll()
  }

  func value() async throws -> StreamTextFinalResult<OUT> {
    if let result {
      switch result {
      case .success(let value): return value
      case .failure(let error): throw error
      }
    }
    return try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }
}

@_spi(Advanced)
public func streamText<OUT: OutputSpec>(_ options: StreamTextOptions<OUT>) -> StreamTextResult<OUT> {
  let collector = StreamTextCollector<OUT>()

  var fullContinuation: AsyncThrowingStream<TextStreamPart, Error>.Continuation?
  var textContinuation: AsyncThrowingStream<String, Error>.Continuation?
  var partialContinuation: AsyncThrowingStream<OUT.Partial, Error>.Continuation?

  let fullStream = AsyncThrowingStream(TextStreamPart.self) { continuation in
    fullContinuation = continuation
  }

  let textStream = AsyncThrowingStream(String.self) { continuation in
    textContinuation = continuation
  }

  let partialStream = AsyncThrowingStream(OUT.Partial.self) { continuation in
    partialContinuation = continuation
  }

  Task {
    do {
      let result = try await runStreamText(
        options: options,
        fullContinuation: fullContinuation,
        textContinuation: textContinuation,
        partialContinuation: partialContinuation
      )
      await collector.resolve(result)
      fullContinuation?.finish()
      textContinuation?.finish()
      partialContinuation?.finish()
    } catch {
      await collector.reject(error)
      if case AIKitError.invalidConfiguration = error {
        fullContinuation?.finish()
        textContinuation?.finish()
        partialContinuation?.finish()
      } else {
        fullContinuation?.finish(throwing: error)
        textContinuation?.finish(throwing: error)
        partialContinuation?.finish(throwing: error)
      }
    }
  }

  return .init(
    textStream: textStream,
    fullStream: fullStream,
    partialOutputStream: partialStream,
    collector: collector
  )
}

@_spi(Advanced)
public func streamText<OUT: OutputSpec>(
  model: any LanguageModel,
  system: SystemPrompt? = nil,
  prompt: String,
  tools: ToolRegistry? = nil,
  toolChoice: ToolChoice = .auto,
  activeTools: [String]? = nil,
  settings: CallSettings = .init(),
  headers: [String: String]? = nil,
  providerOptions: ProviderOptions? = nil,
  maxRetries: Int = 2,
  cancellationToken: CancellationToken? = nil,
  prepareStep: PrepareStepFunction? = nil,
  repairToolCall: ToolCallRepairFunction? = nil,
  download: DownloadFunction? = nil,
  includeRawParts: Bool = false,
  transform: StreamTextTransform? = nil,
  stopWhen: [StopCondition] = [Stop.stepCountIs(1)],
  output: OUT
) -> StreamTextResult<OUT> {
  streamText(.init(
    model: model,
    system: system,
    prompt: prompt,
    messages: nil,
    tools: tools,
    toolChoice: toolChoice,
    activeTools: activeTools,
    settings: settings,
    headers: headers,
    providerOptions: providerOptions,
    maxRetries: maxRetries,
    cancellationToken: cancellationToken,
    prepareStep: prepareStep,
    repairToolCall: repairToolCall,
    download: download,
    includeRawParts: includeRawParts,
    transform: transform,
    stopWhen: stopWhen,
    output: output
  ))
}

@_spi(Advanced)
public func streamText<OUT: OutputSpec>(
  model: any LanguageModel,
  system: SystemPrompt? = nil,
  messages: [ModelMessage],
  tools: ToolRegistry? = nil,
  toolChoice: ToolChoice = .auto,
  activeTools: [String]? = nil,
  settings: CallSettings = .init(),
  headers: [String: String]? = nil,
  providerOptions: ProviderOptions? = nil,
  maxRetries: Int = 2,
  cancellationToken: CancellationToken? = nil,
  prepareStep: PrepareStepFunction? = nil,
  repairToolCall: ToolCallRepairFunction? = nil,
  download: DownloadFunction? = nil,
  includeRawParts: Bool = false,
  transform: StreamTextTransform? = nil,
  stopWhen: [StopCondition] = [Stop.stepCountIs(1)],
  output: OUT
) -> StreamTextResult<OUT> {
  streamText(.init(
    model: model,
    system: system,
    prompt: nil,
    messages: messages,
    tools: tools,
    toolChoice: toolChoice,
    activeTools: activeTools,
    settings: settings,
    headers: headers,
    providerOptions: providerOptions,
    maxRetries: maxRetries,
    cancellationToken: cancellationToken,
    prepareStep: prepareStep,
    repairToolCall: repairToolCall,
    download: download,
    includeRawParts: includeRawParts,
    transform: transform,
    stopWhen: stopWhen,
    output: output
  ))
}

private struct RecordedContentItem: Sendable {
  enum Kind: Sendable {
    case text(String)
    case reasoning(String)
    case part(ContentPart)
  }

  let kind: Kind

  static func text(_ id: String) -> RecordedContentItem { .init(kind: .text(id)) }
  static func reasoning(_ id: String) -> RecordedContentItem { .init(kind: .reasoning(id)) }
  static func part(_ part: ContentPart) -> RecordedContentItem { .init(kind: .part(part)) }
}

private struct TextContentState: Sendable {
  var text: String
  var providerMetadata: ProviderMetadata?
}

private final class ApprovalIDGenerator: @unchecked Sendable {
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

private func runStreamText<OUT: OutputSpec>(
  options: StreamTextOptions<OUT>,
  fullContinuation: AsyncThrowingStream<TextStreamPart, Error>.Continuation?,
  textContinuation: AsyncThrowingStream<String, Error>.Continuation?,
  partialContinuation: AsyncThrowingStream<OUT.Partial, Error>.Continuation?
) async throws -> StreamTextFinalResult<OUT> {
  var steps: [StepResult] = []
  var totalUsage = Usage()
  var responseMessagesHistory: [ModelMessage] = []
  var conversationMessages: [ModelMessage] = options.messages ?? []
  if conversationMessages.isEmpty, let prompt = options.prompt {
    conversationMessages = [.user(prompt)]
  }
  let initialMessages = conversationMessages

  let approvalIDGenerator = ApprovalIDGenerator()

  if let tools = options.tools,
     let approvalResults = try? collectToolApprovals(messages: initialMessages),
     approvalResults.approvedToolApprovals.isEmpty == false
      || approvalResults.deniedToolApprovals.isEmpty == false {
    let toolMessage = await executeApprovals(
      approvals: approvalResults,
      tools: tools,
      messages: initialMessages,
      experimentalContext: options.experimentalContext
    )
    if toolMessage.content.isEmpty == false {
      responseMessagesHistory.append(toolMessage)
    }
  }

  fullContinuation?.yield(.start)

  while true {
    let stepInputMessages = initialMessages + responseMessagesHistory
    let prepareResult = await options.prepareStep?(
      .init(
        steps: steps,
        stepNumber: steps.count,
        model: options.model,
        messages: stepInputMessages,
        experimentalContext: options.experimentalContext
      )
    )

    let stepModel = prepareResult?.model ?? options.model
    let stepToolChoice = prepareResult?.toolChoice ?? options.toolChoice
    let stepActiveTools = prepareResult?.activeTools ?? options.activeTools
    let stepSystem = prepareResult?.system ?? options.system
    let stepMessages = prepareResult?.messages ?? stepInputMessages
    let stepProviderOptions = prepareResult?.providerOptions ?? options.providerOptions
    let stepExperimentalContext = prepareResult?.experimentalContext ?? options.experimentalContext

    let requestMessages = normalizeSystemMessages(stepSystem) + stepMessages
    let preparedMessages = try await prepareMessagesForModel(
      messages: requestMessages,
      model: stepModel,
      download: options.download
    )
    let toolDefinitions = toolDefinitions(
      from: options.tools,
      activeTools: stepActiveTools,
      toolChoice: stepToolChoice
    )

    let request = ModelRequest(
      messages: preparedMessages,
      responseFormat: options.output.responseFormat,
      tools: toolDefinitions,
      toolChoice: stepToolChoice,
      settings: options.settings,
      headers: options.headers,
      providerOptions: stepProviderOptions,
      cancellationToken: options.cancellationToken
    )

    let baseStream = stepModel.stream(request)
    let stepResponseBox = Locked(LanguageModelResponseMetadata())

    let tappedStream = AsyncThrowingStream(ModelStreamPart.self) { continuation in
      let continuationBox = UnsafeSendable(value: continuation)
      Task {
        let continuation = continuationBox.value
        do {
          for try await part in baseStream {
            if case let .responseMetadata(response) = part {
              stepResponseBox.withLock { $0 = response }
            }
            continuation.yield(part)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }

    let generateID: @Sendable () -> String = {
      approvalIDGenerator.generate()
    }

    let streamWithTools = runToolsTransformation(
      .init(
        generateID: generateID,
        generatorStream: tappedStream,
        tools: options.tools,
        messages: stepInputMessages,
        system: stepSystem,
        repairToolCall: options.repairToolCall,
        experimentalContext: stepExperimentalContext
      )
    )

    let processedStream = options.transform?(streamWithTools) ?? streamWithTools

    var recordedItems: [RecordedContentItem] = []
    var textStateByID: [String: TextContentState] = [:]
    var reasoningStateByID: [String: TextContentState] = [:]
    var stepWarnings: [CallWarning] = []
    var stepRequest = LanguageModelRequestMetadata()
    var stepFinishReason: FinishReason = .other
    var stepRawFinishReason: String?
    var stepUsage = Usage()
    var stepProviderMetadata: ProviderMetadata?
    var stepHasStarted = false
    var stepTextBuffer = ""
    var activeToolCallNames: [String: String] = [:]
    var abortRequested = false
    var hasToolApprovalRequest = false

    var streamThrew = false
    do {
      for try await part in processedStream {
        if let token = options.cancellationToken, await token.isCancelled {
          fullContinuation?.yield(.abort)
          await options.onAbort?()
          stepFinishReason = .error
          stepHasStarted = true
          abortRequested = true
          break
        }

        switch part {
        case .start:
          continue
        case .startStep(let request, let warnings):
          stepRequest = request
          stepWarnings = warnings
          continue
        default:
          break
        }

        if stepHasStarted == false {
          stepHasStarted = true
          fullContinuation?.yield(.startStep(request: stepRequest, warnings: stepWarnings))
        }

        switch part {
      case .textStart(let id, let providerMetadata):
        textStateByID[id] = .init(text: "", providerMetadata: providerMetadata)
        recordedItems.append(.text(id))
        fullContinuation?.yield(part)
      case .textDelta(let id, let text, let providerMetadata):
        guard text.isEmpty == false else { break }
        guard var state = textStateByID[id] else {
          let message = "text part \(id) not found"
          fullContinuation?.yield(.error(message))
          await options.onError?(message)
          break
        }
        state.text += text
        if let providerMetadata { state.providerMetadata = providerMetadata }
        textStateByID[id] = state
        fullContinuation?.yield(.textDelta(id: id, text: text, providerMetadata: providerMetadata))
        textContinuation?.yield(text)
        stepTextBuffer += text
        if let partial = await options.output.parsePartial(text: stepTextBuffer) {
          partialContinuation?.yield(partial)
        }
        await options.onChunk?(.textDelta(id: id, text: text, providerMetadata: providerMetadata))
      case .textEnd(let id, let providerMetadata):
        guard var state = textStateByID[id] else {
          let message = "text part \(id) not found"
          fullContinuation?.yield(.error(message))
          await options.onError?(message)
          break
        }
        if let providerMetadata { state.providerMetadata = providerMetadata }
        textStateByID[id] = state
        fullContinuation?.yield(part)
      case .reasoningStart(let id, let providerMetadata):
        reasoningStateByID[id] = .init(text: "", providerMetadata: providerMetadata)
        recordedItems.append(.reasoning(id))
        fullContinuation?.yield(part)
      case .reasoningDelta(let id, let text, let providerMetadata):
        guard var state = reasoningStateByID[id] else {
          let message = "reasoning part \(id) not found"
          fullContinuation?.yield(.error(message))
          await options.onError?(message)
          break
        }
        state.text += text
        if let providerMetadata { state.providerMetadata = providerMetadata }
        reasoningStateByID[id] = state
        fullContinuation?.yield(part)
        await options.onChunk?(.reasoningDelta(id: id, text: text, providerMetadata: providerMetadata))
      case .reasoningEnd(let id, let providerMetadata):
        guard var state = reasoningStateByID[id] else {
          let message = "reasoning part \(id) not found"
          fullContinuation?.yield(.error(message))
          await options.onError?(message)
          break
        }
        if let providerMetadata { state.providerMetadata = providerMetadata }
        reasoningStateByID[id] = state
        fullContinuation?.yield(part)
      case .toolInputStart(let id, let toolName, let providerMetadata, let providerExecuted, let dynamic, let title):
        activeToolCallNames[id] = toolName
        if let tools = options.tools,
           let toolBox = tools.toolBox(named: toolName) {
          let context = ToolContext(
            toolCallID: id,
            messages: stepInputMessages,
            experimentalContext: stepExperimentalContext
          )
          await toolBox.onInputStart(context: context)
        }
        fullContinuation?.yield(
          .toolInputStart(
            id: id,
            toolName: toolName,
            providerMetadata: providerMetadata,
            providerExecuted: providerExecuted,
            dynamic: dynamic,
            title: title
          )
        )
        await options.onChunk?(
          .toolInputStart(
            id: id,
            toolName: toolName,
            providerMetadata: providerMetadata,
            providerExecuted: providerExecuted,
            dynamic: dynamic,
            title: title
          )
        )
      case .toolInputDelta(let id, let delta, let providerMetadata):
        if let toolName = activeToolCallNames[id],
           let tools = options.tools,
           let toolBox = tools.toolBox(named: toolName) {
          let context = ToolContext(
            toolCallID: id,
            messages: stepInputMessages,
            experimentalContext: stepExperimentalContext
          )
          await toolBox.onInputDelta(delta, context: context)
        }
        fullContinuation?.yield(.toolInputDelta(id: id, delta: delta, providerMetadata: providerMetadata))
        await options.onChunk?(.toolInputDelta(id: id, delta: delta, providerMetadata: providerMetadata))
      case .toolInputEnd(let id, let providerMetadata):
        activeToolCallNames.removeValue(forKey: id)
        fullContinuation?.yield(.toolInputEnd(id: id, providerMetadata: providerMetadata))
      case .source(let source):
        recordedItems.append(.part(.source(source)))
        fullContinuation?.yield(.source(source))
        await options.onChunk?(.source(source))
      case .file(let file):
        recordedItems.append(.part(.file(file)))
        fullContinuation?.yield(.file(file))
      case .toolCall(let call):
        recordedItems.append(.part(.toolCall(call)))
        fullContinuation?.yield(.toolCall(call))
        await options.onChunk?(.toolCall(call))
      case .toolResult(let result):
        if result.preliminary == false {
          recordedItems.append(.part(.toolResult(result)))
        }
        fullContinuation?.yield(.toolResult(result))
        await options.onChunk?(.toolResult(result))
      case .toolError(let error):
        recordedItems.append(.part(.toolError(error)))
        fullContinuation?.yield(.toolError(error))
        await options.onChunk?(.toolError(error))
      case .toolOutputDenied(let denied):
        recordedItems.append(.part(.toolOutputDenied(denied)))
        fullContinuation?.yield(.toolOutputDenied(denied))
      case .toolApprovalRequest(let request):
        recordedItems.append(.part(.toolApprovalRequest(request)))
        hasToolApprovalRequest = true
        fullContinuation?.yield(.toolApprovalRequest(request))
      case .toolApprovalResponse(let response):
        recordedItems.append(.part(.toolApprovalResponse(response)))
        fullContinuation?.yield(.toolApprovalResponse(response))
      case .raw(let value):
        if options.includeRawParts {
          fullContinuation?.yield(.raw(value))
          await options.onChunk?(.raw(value))
        }
      case .error(let message):
        fullContinuation?.yield(.error(message))
        stepFinishReason = .error
        await options.onError?(message)
      case .finish(let finishReason, let rawFinishReason, let totalUsage):
        stepFinishReason = finishReason
        stepRawFinishReason = rawFinishReason
        stepUsage = totalUsage
      case .finishStep(let response, let usage, let finishReason, let rawFinishReason, let providerMetadata):
        stepResponseBox.withLock { $0 = response }
        stepUsage = usage
        stepFinishReason = finishReason
        stepRawFinishReason = rawFinishReason
        stepProviderMetadata = providerMetadata
      case .abort:
        fullContinuation?.yield(.abort)
        await options.onAbort?()
        case .start, .startStep:
          break
        }
      }
    } catch {
      let message = error.localizedDescription
      fullContinuation?.yield(.error(message))
      await options.onError?(message)
      streamThrew = true
    }

    if streamThrew {
      break
    }

    if stepHasStarted == false {
      break
    }

    let stepContent = buildContent(
      recordedItems: recordedItems,
      textStateByID: textStateByID,
      reasoningStateByID: reasoningStateByID
    )
    let stepResponseMessages = toResponseMessages(stepContent)

    let stepResult = StepResult(
      content: stepContent,
      finishReason: stepFinishReason,
      rawFinishReason: stepRawFinishReason,
      usage: stepUsage,
      warnings: stepWarnings,
      request: stepRequest,
      response: stepResponseBox.get(),
      responseMessages: responseMessagesHistory + stepResponseMessages,
      providerMetadata: stepProviderMetadata
    )

    await options.onStepFinish?(stepResult)
    steps.append(stepResult)
    responseMessagesHistory.append(contentsOf: stepResponseMessages)
    totalUsage = totalUsage.adding(stepUsage)

    fullContinuation?.yield(
      .finishStep(
        response: stepResponseBox.get(),
        usage: stepUsage,
        finishReason: stepFinishReason,
        rawFinishReason: stepRawFinishReason,
        providerMetadata: stepProviderMetadata
      )
    )

    if abortRequested {
      break
    }

    if hasToolApprovalRequest {
      break
    }

    let shouldStop = await isStopConditionMet(options.stopWhen, steps: steps)

    if stepFinishReason == .toolCalls && shouldStop == false {
      continue
    }

    break
  }

  guard let lastStep = steps.last else {
    throw AIKitError.invalidConfiguration("No output generated. Check the stream for errors.")
  }

  let outputContext = OutputContext(
    finishReason: lastStep.finishReason,
    usage: lastStep.usage,
    providerMetadata: lastStep.providerMetadata,
    response: lastStep.response
  )

  var outputValue: OUT.Complete?
  var outputError: Error?
  do {
    outputValue = try await options.output.parseComplete(text: lastStep.text, context: outputContext)
  } catch {
    outputError = error
  }

  let finishReason = lastStep.finishReason
  let rawFinishReason = lastStep.rawFinishReason

  fullContinuation?.yield(
    .finish(
      finishReason: finishReason,
      rawFinishReason: rawFinishReason,
      totalUsage: totalUsage
    )
  )

  await options.onFinish?(
    .init(
      steps: steps,
      totalUsage: totalUsage,
      finishReason: finishReason,
      rawFinishReason: rawFinishReason,
      providerMetadata: lastStep.providerMetadata,
      experimentalContext: options.experimentalContext,
      output: outputValue
    )
  )

  return .init(
    steps: steps,
    totalUsage: totalUsage,
    finishReason: finishReason,
    rawFinishReason: rawFinishReason,
    outputValue: outputValue,
    outputError: outputError
  )
}

private func buildContent(
  recordedItems: [RecordedContentItem],
  textStateByID: [String: TextContentState],
  reasoningStateByID: [String: TextContentState]
) -> [ContentPart] {
  var content: [ContentPart] = []
  for item in recordedItems {
    switch item.kind {
    case .text(let id):
      if let state = textStateByID[id] {
        content.append(.text(state.text, providerMetadata: state.providerMetadata))
      }
    case .reasoning(let id):
      if let state = reasoningStateByID[id] {
        content.append(.reasoning(state.text, providerMetadata: state.providerMetadata))
      }
    case .part(let part):
      content.append(part)
    }
  }
  return content
}

private func normalizeSystemMessages(_ system: SystemPrompt?) -> [ModelMessage] {
  guard let system else { return [] }
  switch system {
  case .text(let text):
    return [.system(text)]
  case .message(let message):
    guard message.role == .system else {
      return []
    }
    return [message]
  case .messages(let messages):
    guard messages.allSatisfy({ $0.role == .system }) else {
      return []
    }
    return messages
  }
}

private func toolDefinitions(
  from registry: ToolRegistry?,
  activeTools: [String]?,
  toolChoice: ToolChoice
) -> [ToolDefinition] {
  guard let registry, toolChoice != .none else { return [] }
  var definitions = registry.definitions
  if let activeTools {
    let allowed = Set(activeTools)
    definitions = definitions.filter { allowed.contains($0.name) }
  }
  return definitions
}

private func toResponseMessages(_ content: [ContentPart]) -> [ModelMessage] {
  var assistantParts: [ModelMessagePart] = []
  var toolParts: [ModelMessagePart] = []

  for part in content {
    switch part {
    case .text(let text, let metadata):
      assistantParts.append(
        .text(
          .init(
            text: text,
            providerOptions: providerOptions(from: metadata)
          )
        )
      )
    case .reasoning(let text, let metadata):
      assistantParts.append(
        .reasoning(
          .init(
            text: text,
            providerOptions: providerOptions(from: metadata)
          )
        )
      )
    case .toolCall(let call):
      assistantParts.append(.toolCall(call))
    case .toolApprovalRequest(let request):
      assistantParts.append(.toolApprovalRequest(
        .init(
          approvalID: request.approvalID,
          toolCallID: request.toolCallID,
          toolCall: nil
        )
      ))
    case .toolApprovalResponse(let response):
      toolParts.append(.toolApprovalResponse(response))
    case .toolResult(let result):
      toolParts.append(.toolResult(result))
    case .toolError(let error):
      toolParts.append(.toolError(error))
    case .toolOutputDenied(let denied):
      toolParts.append(.toolOutputDenied(denied))
    case .source, .file:
      break
    }
  }

  var messages: [ModelMessage] = []
  if assistantParts.isEmpty == false {
    messages.append(.init(role: .assistant, content: assistantParts))
  }
  if toolParts.isEmpty == false {
    messages.append(.init(role: .tool, content: toolParts))
  }
  return messages
}

private func providerOptions(from metadata: ProviderMetadata?) -> ProviderOptions? {
  guard let metadata else { return nil }
  var options: ProviderOptions = [:]
  for (key, value) in metadata {
    if case let .object(object) = value {
      options[key] = object
    }
  }
  return options.isEmpty ? nil : options
}

private func isStopConditionMet(_ conditions: [StopCondition], steps: [StepResult]) async -> Bool {
  for condition in conditions {
    if await condition(steps) {
      return true
    }
  }
  return false
}

private func executeApprovals(
  approvals: ToolApprovalsCollection,
  tools: ToolRegistry,
  messages: [ModelMessage],
  experimentalContext: AnySendable?
) async -> ModelMessage {
  var parts: [ModelMessagePart] = []

  for approval in approvals.approvedToolApprovals {
    let call = approval.toolCall
    if call.providerExecuted == true {
      continue
    }
    guard let toolBox = tools.toolBox(named: call.toolName),
          let input = call.input,
          let inputAny = try? toolBox.decodeInput(from: input)
    else {
      continue
    }
    let context = ToolContext(
      toolCallID: call.toolCallID,
      messages: messages,
      experimentalContext: experimentalContext
    )
    if let execution = try? await toolBox.execute(inputAny, context: context) {
      switch execution {
      case .final(let output):
        let jsonValue = (try? toolBox.encodeOutput(output)) ?? .null
        let modelOutput = toolModelOutput(from: jsonValue, errorText: nil) ?? .null
        parts.append(
          .toolResult(
            .init(
              toolCallID: call.toolCallID,
              toolName: call.toolName,
              inputJSON: nil,
              input: nil,
              output: modelOutput,
              preliminary: false,
              providerExecuted: call.providerExecuted,
              dynamic: call.dynamic,
              title: call.title,
              providerMetadata: call.providerMetadata
            )
          )
        )
      case .streaming(let stream):
        do {
          for try await progress in stream {
            switch progress {
            case .preliminary(let output):
              let jsonValue = (try? toolBox.encodeOutput(output)) ?? .null
              let modelOutput = toolModelOutput(from: jsonValue, errorText: nil) ?? .null
              parts.append(
                .toolResult(
                  .init(
                    toolCallID: call.toolCallID,
                    toolName: call.toolName,
                    inputJSON: nil,
                    input: nil,
                    output: modelOutput,
                    preliminary: true,
                    providerExecuted: call.providerExecuted,
                    dynamic: call.dynamic,
                    title: call.title,
                    providerMetadata: call.providerMetadata
                  )
                )
              )
            case .final(let output):
              let jsonValue = (try? toolBox.encodeOutput(output)) ?? .null
              let modelOutput = toolModelOutput(from: jsonValue, errorText: nil) ?? .null
              parts.append(
                .toolResult(
                  .init(
                    toolCallID: call.toolCallID,
                    toolName: call.toolName,
                    inputJSON: nil,
                    input: nil,
                    output: modelOutput,
                    preliminary: false,
                    providerExecuted: call.providerExecuted,
                    dynamic: call.dynamic,
                    title: call.title,
                    providerMetadata: call.providerMetadata
                  )
                )
              )
            }
          }
        } catch {
          parts.append(
            .toolError(
              .init(
                toolCallID: call.toolCallID,
                toolName: call.toolName,
                inputJSON: call.inputJSON,
                input: call.input,
                error: "Tool execution failed: \(error)",
                providerExecuted: call.providerExecuted,
                dynamic: call.dynamic,
                title: call.title,
                providerMetadata: call.providerMetadata
              )
            )
          )
        }
      }
    }
  }

  for approval in approvals.deniedToolApprovals {
    let call = approval.toolCall
    if call.providerExecuted == true {
      continue
    }
    let reason = approval.approvalResponse.reason ?? "Tool execution denied."
    let modelOutput = toolModelOutput(from: nil, errorText: reason) ?? .null
    parts.append(
      .toolResult(
        .init(
          toolCallID: call.toolCallID,
          toolName: call.toolName,
          inputJSON: nil,
          input: nil,
          output: modelOutput,
          preliminary: nil,
          providerExecuted: call.providerExecuted,
          dynamic: call.dynamic,
          title: call.title,
          providerMetadata: call.providerMetadata
        )
      )
    )
  }

  return .init(role: .tool, content: parts)
}

private func toolModelOutput(from output: JSONValue?, errorText: String?) -> JSONValue? {
  if let errorText {
    return .object(["type": .string("error-text"), "value": .string(errorText)])
  }

  guard let output else { return nil }

  switch output {
  case .string(let value):
    return .object(["type": .string("text"), "value": .string(value)])
  default:
    return .object(["type": .string("json"), "value": output])
  }
}

private extension Usage {
  func adding(_ other: Usage) -> Usage {
    let input = sum(inputTokens, other.inputTokens)
    let output = sum(outputTokens, other.outputTokens)
    return .init(inputTokens: input, outputTokens: output)
  }

  private func sum(_ lhs: InputTokens?, _ rhs: InputTokens?) -> InputTokens? {
    guard lhs != nil || rhs != nil else { return nil }
    return .init(
      total: sum(lhs?.total, rhs?.total),
      noCache: sum(lhs?.noCache, rhs?.noCache),
      cacheRead: sum(lhs?.cacheRead, rhs?.cacheRead),
      cacheWrite: sum(lhs?.cacheWrite, rhs?.cacheWrite)
    )
  }

  private func sum(_ lhs: OutputTokens?, _ rhs: OutputTokens?) -> OutputTokens? {
    guard lhs != nil || rhs != nil else { return nil }
    return .init(
      total: sum(lhs?.total, rhs?.total),
      text: sum(lhs?.text, rhs?.text),
      reasoning: sum(lhs?.reasoning, rhs?.reasoning)
    )
  }

  private func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
    guard lhs != nil || rhs != nil else { return nil }
    return (lhs ?? 0) + (rhs ?? 0)
  }
}
