import Foundation
import AIKitProviders

public struct GenerateTextOptions<OUT: OutputSpec>: Sendable {
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

  public var stopWhen: [StopCondition]
  public var output: OUT

  public var experimentalContext: AnySendable?

  public var onStepFinish: (@Sendable (StepResult) async -> Void)?
  public var onFinish: (@Sendable (GenerateTextFinishEvent<OUT>) async -> Void)?

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
    stopWhen: [StopCondition] = [Stop.stepCountIs(1)],
    output: OUT,
    experimentalContext: AnySendable? = nil,
    onStepFinish: (@Sendable (StepResult) async -> Void)? = nil,
    onFinish: (@Sendable (GenerateTextFinishEvent<OUT>) async -> Void)? = nil
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
    self.stopWhen = stopWhen
    self.output = output
    self.experimentalContext = experimentalContext
    self.onStepFinish = onStepFinish
    self.onFinish = onFinish
  }
}

public struct GenerateTextFinishEvent<OUT: OutputSpec>: Sendable {
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

public struct GenerateTextResult<OUT: OutputSpec>: Sendable {
  public var steps: [StepResult]
  public var totalUsage: Usage
  var outputValue: OUT.Complete?
  var outputError: Error?

  public init(
    steps: [StepResult] = [],
    totalUsage: Usage = .init(),
    outputValue: OUT.Complete? = nil,
    outputError: Error? = nil
  ) {
    self.steps = steps
    self.totalUsage = totalUsage
    self.outputValue = outputValue
    self.outputError = outputError
  }

  public var content: [ContentPart] { steps.last?.content ?? [] }
  public var text: String { steps.last?.text ?? "" }
  public var reasoning: [ReasoningOutput] {
    content.compactMap { part in
      if case let .reasoning(text, metadata) = part {
        return .init(text: text, providerMetadata: metadata)
      }
      return nil
    }
  }
  public var reasoningText: String? {
    let combined = reasoning.map(\.text).joined()
    return combined.isEmpty ? nil : combined
  }
  public var files: [GeneratedFile] {
    steps.flatMap { step in
      step.content.compactMap { part in
        if case let .file(file) = part { return file }
        return nil
      }
    }
  }
  public var sources: [Source] {
    steps.flatMap { step in
      step.content.compactMap { part in
        if case let .source(source) = part { return source }
        return nil
      }
    }
  }
  public var toolCalls: [ToolCall] { steps.last?.toolCalls ?? [] }
  public var toolResults: [ToolResult] { steps.last?.toolResults ?? [] }

  public var finishReason: FinishReason { steps.last?.finishReason ?? .other }
  public var rawFinishReason: String? { steps.last?.rawFinishReason }
  public var usage: Usage { steps.last?.usage ?? .init() }
  public var warnings: [CallWarning]? { steps.last?.warnings }
  public var request: LanguageModelRequestMetadata { steps.last?.request ?? .init() }
  public var response: LanguageModelResponseMetadata { steps.last?.response ?? .init() }
  public var responseMessages: [ModelMessage] { steps.last?.responseMessages ?? [] }
  public var providerMetadata: ProviderMetadata? { steps.last?.providerMetadata }

  public var experimental_output: OUT.Complete {
    get throws { try output }
  }

  public var output: OUT.Complete {
    get throws {
      if let error = outputError { throw error }
      if let outputValue { return outputValue }
      throw AIKitError.invalidConfiguration("No output generated.")
    }
  }
}

@_spi(Advanced)
public func generateText<OUT: OutputSpec>(_ options: GenerateTextOptions<OUT>) async throws -> GenerateTextResult<OUT> {
  var steps: [StepResult] = []
  var totalUsage = Usage()
  var responseMessagesHistory: [ModelMessage] = []
  var pendingDeferredToolCalls: Set<String> = []
  var conversationMessages: [ModelMessage] = options.messages ?? []
  if conversationMessages.isEmpty, let prompt = options.prompt {
    conversationMessages = [.user(prompt)]
  }
  let initialMessages = conversationMessages

  var approvalCounter = 0
  func generateApprovalID() -> String {
    let value = "id-\(approvalCounter)"
    approvalCounter += 1
    return value
  }

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

    let response = try await stepModel.generate(request)

    var contentParts: [ContentPart] = []
    var stepToolCalls: [ParsedToolCall] = []

    for part in response.content {
      switch part {
      case .text(let text, let metadata):
        contentParts.append(.text(text, providerMetadata: metadata))
      case .reasoning(let text, let metadata):
        contentParts.append(.reasoning(text, providerMetadata: metadata))
      case .toolCall(let call):
        let parsed = await parseToolCall(
          .init(
            toolCall: call,
            tools: options.tools,
            repairToolCall: options.repairToolCall,
            messages: stepInputMessages,
            system: stepSystem
          )
        )
        let dynamicFlag = parsed.invalid ? true : parsed.dynamic
        let toolCall = ToolCall(
          toolCallID: parsed.toolCallID,
          toolName: parsed.toolName,
          inputJSON: call.inputJSON,
          input: parsed.input,
          invalid: parsed.invalid ? true : nil,
          error: parsed.error?.message,
          providerExecuted: parsed.providerExecuted,
          dynamic: dynamicFlag,
          title: parsed.title,
          providerMetadata: parsed.providerMetadata
        )
        contentParts.append(.toolCall(toolCall))
        stepToolCalls.append(parsed)
      case .toolResult(let result):
        contentParts.append(.toolResult(result))
      case .toolError(let error):
        contentParts.append(.toolError(error))
      case .toolOutputDenied(let denied):
        contentParts.append(.toolOutputDenied(denied))
      case .toolApprovalRequest(let request):
        var enriched = request
        if enriched.toolCall == nil {
          if let call = contentParts.compactMap({ part -> ToolCall? in
            if case let .toolCall(call) = part { return call }
            return nil
          }).first(where: { $0.toolCallID == request.toolCallID }) {
            enriched = .init(
              approvalID: request.approvalID,
              toolCallID: request.toolCallID,
              toolCall: call
            )
          }
        }
        contentParts.append(.toolApprovalRequest(enriched))
      case .source(let source):
        contentParts.append(.source(source))
      case .file(let file):
        contentParts.append(.file(file))
      }
    }

    var toolMessageParts: [ContentPart] = []
    var pendingApprovals: [ToolApprovalRequest] = []
    var clientToolCalls: [ParsedToolCall] = []
    var clientToolOutputs: [ContentPart] = []

    if let tools = options.tools {
      for parsed in stepToolCalls {
        if parsed.invalid { continue }
        guard let toolBox = tools.toolBox(named: parsed.toolName) else { continue }

        let context = ToolContext(
          toolCallID: parsed.toolCallID,
          messages: stepInputMessages,
          experimentalContext: stepExperimentalContext
        )

        guard let inputAny = try? toolBox.decodeInput(from: parsed.input) else { continue }

        await toolBox.onInputAvailable(inputAny, context: context)

        if let needsApproval = await toolBox.needsApproval(inputAny, context: context), needsApproval {
          let request = ToolApprovalRequest(
            approvalID: generateApprovalID(),
            toolCallID: parsed.toolCallID,
            toolCall: ToolCall(
              toolCallID: parsed.toolCallID,
              toolName: parsed.toolName,
              inputJSON: "",
              input: parsed.input,
              providerExecuted: parsed.providerExecuted,
              dynamic: parsed.dynamic,
              title: parsed.title,
              providerMetadata: parsed.providerMetadata
            )
          )
          pendingApprovals.append(request)
        }
      }
    }

    // invalid tool calls produce tool errors (dynamic) so they count as outputs:
    let invalidToolCalls = stepToolCalls.filter { $0.invalid }
    for parsed in invalidToolCalls {
      if let error = parsed.error {
        let part: ContentPart = .toolError(
          .init(
            toolCallID: parsed.toolCallID,
            toolName: parsed.toolName,
            inputJSON: "",
            input: parsed.input,
            error: error.message,
            providerExecuted: parsed.providerExecuted,
            dynamic: parsed.dynamic ?? true,
            title: parsed.title,
            providerMetadata: parsed.providerMetadata
          )
        )
        contentParts.append(part)
        clientToolOutputs.append(part)
      }
    }

    clientToolCalls = stepToolCalls.filter { $0.providerExecuted != true }

    if let tools = options.tools {
      for parsed in clientToolCalls {
        if parsed.invalid { continue }
        if pendingApprovals.contains(where: { $0.toolCallID == parsed.toolCallID }) {
          continue
        }
        guard let toolBox = tools.toolBox(named: parsed.toolName) else { continue }
        let context = ToolContext(
          toolCallID: parsed.toolCallID,
          messages: stepInputMessages,
          experimentalContext: stepExperimentalContext
        )
        guard let inputAny = try? toolBox.decodeInput(from: parsed.input) else { continue }

        if parsed.providerExecuted == true {
          continue
        }

        do {
          guard let execution = try await toolBox.execute(inputAny, context: context) else {
            continue
          }

          switch execution {
          case .final(let output):
            let jsonValue = (try? toolBox.encodeOutput(output)) ?? .null
            let result = ToolResult(
              toolCallID: parsed.toolCallID,
              toolName: parsed.toolName,
              inputJSON: nil,
              input: parsed.input,
              output: jsonValue,
              preliminary: false,
              providerExecuted: parsed.providerExecuted,
              dynamic: parsed.dynamic ?? false,
              title: parsed.title,
              providerMetadata: parsed.providerMetadata
            )
            let part: ContentPart = .toolResult(result)
            contentParts.append(part)
            toolMessageParts.append(part)
            clientToolOutputs.append(part)
          case .streaming(let stream):
            for try await progress in stream {
              switch progress {
              case .preliminary(let output):
                let jsonValue = (try? toolBox.encodeOutput(output)) ?? .null
                let result = ToolResult(
                  toolCallID: parsed.toolCallID,
                  toolName: parsed.toolName,
                  inputJSON: nil,
                  input: parsed.input,
                  output: jsonValue,
                  preliminary: true,
                  providerExecuted: parsed.providerExecuted,
                  dynamic: parsed.dynamic ?? false,
                  title: parsed.title,
                  providerMetadata: parsed.providerMetadata
                )
                let part: ContentPart = .toolResult(result)
                contentParts.append(part)
                toolMessageParts.append(part)
                clientToolOutputs.append(part)
              case .final(let output):
                let jsonValue = (try? toolBox.encodeOutput(output)) ?? .null
                let result = ToolResult(
                  toolCallID: parsed.toolCallID,
                  toolName: parsed.toolName,
                  inputJSON: nil,
                  input: parsed.input,
                  output: jsonValue,
                  preliminary: false,
                  providerExecuted: parsed.providerExecuted,
                  dynamic: parsed.dynamic ?? false,
                  title: parsed.title,
                  providerMetadata: parsed.providerMetadata
                )
                let part: ContentPart = .toolResult(result)
                contentParts.append(part)
                toolMessageParts.append(part)
                clientToolOutputs.append(part)
              }
            }
          }
        } catch {
          let part: ContentPart = .toolError(
            .init(
              toolCallID: parsed.toolCallID,
              toolName: parsed.toolName,
              inputJSON: nil,
              input: parsed.input,
              error: "Tool execution failed: \(error)",
              providerExecuted: parsed.providerExecuted,
              dynamic: parsed.dynamic ?? false,
              title: parsed.title,
              providerMetadata: parsed.providerMetadata
            )
          )
          contentParts.append(part)
          toolMessageParts.append(part)
          clientToolOutputs.append(part)
        }
      }
    }

    for request in pendingApprovals {
      contentParts.append(.toolApprovalRequest(request))
    }

    if let tools = options.tools {
      for parsed in stepToolCalls {
        guard parsed.providerExecuted == true else { continue }
        guard let kind = tools.toolKind(named: parsed.toolName) else { continue }
        if case let .provider(supportsDeferredResults) = kind, supportsDeferredResults {
          let hasResultInResponse = response.content.contains { part in
            if case let .toolResult(result) = part {
              return result.toolCallID == parsed.toolCallID
            }
            return false
          }
          if hasResultInResponse == false {
            pendingDeferredToolCalls.insert(parsed.toolCallID)
          }
        }
      }
    }

    for part in response.content {
      if case let .toolResult(result) = part {
        pendingDeferredToolCalls.remove(result.toolCallID)
      }
    }

    let responseMessages = toResponseMessages(contentParts)
    responseMessagesHistory.append(contentsOf: responseMessages)
    let stepResult = StepResult(
      content: contentParts,
      finishReason: response.finishReason,
      rawFinishReason: response.rawFinishReason,
      usage: response.usage,
      warnings: response.warnings,
      request: response.request,
      response: response.response,
      responseMessages: responseMessagesHistory,
      providerMetadata: response.providerMetadata
    )
    steps.append(stepResult)
    totalUsage = totalUsage.adding(response.usage)

    await options.onStepFinish?(stepResult)

    let shouldStop = await isStopConditionMet(options.stopWhen, steps: steps)
    let shouldContinue = (
      (clientToolCalls.isEmpty == false && clientToolOutputs.count == clientToolCalls.count)
      || pendingDeferredToolCalls.isEmpty == false
    ) && shouldStop == false

    if shouldContinue {
      continue
    }

    break
  }

  let lastStep = steps.last
  var outputValue: OUT.Complete?
  var outputError: Error?

  if let lastStep {
    if lastStep.finishReason != .toolCalls {
      let context = OutputContext(
        finishReason: lastStep.finishReason,
        usage: lastStep.usage,
        providerMetadata: lastStep.providerMetadata,
        response: lastStep.response
      )
      do {
        outputValue = try await options.output.parseComplete(text: lastStep.text, context: context)
      } catch {
        outputError = error
      }
    } else {
      outputError = AIKitError.invalidConfiguration("No output generated.")
    }
  }

  let result = GenerateTextResult<OUT>(
    steps: steps,
    totalUsage: totalUsage,
    outputValue: outputValue,
    outputError: outputError
  )

  if let lastStep {
    await options.onFinish?(
      .init(
        steps: steps,
        totalUsage: totalUsage,
        finishReason: lastStep.finishReason,
        rawFinishReason: lastStep.rawFinishReason,
        providerMetadata: lastStep.providerMetadata,
        experimentalContext: options.experimentalContext,
        output: outputValue
      )
    )
  }

  return result
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
    switch (lhs, rhs) {
    case (nil, nil): return nil
    case (let l?, nil): return l
    case (nil, let r?): return r
    case (let l?, let r?): return l + r
    }
  }
}

@_spi(Advanced)
public func generateText<OUT: OutputSpec>(
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
  stopWhen: [StopCondition] = [Stop.stepCountIs(1)],
  output: OUT
) async throws -> GenerateTextResult<OUT> {
  try await generateText(.init(
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
    stopWhen: stopWhen,
    output: output
  ))
}

@_spi(Advanced)
public func generateText<OUT: OutputSpec>(
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
  stopWhen: [StopCondition] = [Stop.stepCountIs(1)],
  output: OUT
) async throws -> GenerateTextResult<OUT> {
  try await generateText(.init(
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
    stopWhen: stopWhen,
    output: output
  ))
}
