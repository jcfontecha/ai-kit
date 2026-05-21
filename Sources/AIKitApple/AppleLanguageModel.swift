import Foundation
import FoundationModels
import AIKitProviders

struct AppleLanguageModel: LanguageModel, Sendable {
  let id: String
  let capabilities: ModelCapabilities = [.toolCalling, .jsonSchemaOutput]
  let supportedURLs: SupportedURLPatterns = [:]

  private let settings: AppleLanguageModelSettings

  init(settings: AppleLanguageModelSettings) {
    self.settings = settings
    self.id = settings.modelID
  }

  func generate(_ request: ModelRequest) async throws -> ModelResponse {
    if let cancellationToken = request.cancellationToken, await cancellationToken.isCancelled {
      throw CancellationError()
    }

    let prepared = try prepare(request)
    let session = try makeSession(prepared: prepared)
    let startedAt = Date()

    switch prepared.responseMode {
    case .text:
      let response = try await session.respond(
        to: prepared.prompt.prompt,
        options: prepared.generationOptions
      )
      let entries = Array(response.transcriptEntries)
      return modelResponse(
        from: entries,
        outputText: response.content,
        warnings: prepared.warnings,
        timestamp: startedAt
      )

    case .structured(let schema, let includeSchemaInPrompt):
      let response = try await session.respond(
        to: prepared.prompt.prompt,
        schema: schema,
        includeSchemaInPrompt: includeSchemaInPrompt,
        options: prepared.generationOptions
      )
      let entries = Array(response.transcriptEntries)
      let outputText = response.rawContent.jsonString
      return modelResponse(
        from: entries,
        outputText: outputText,
        warnings: prepared.warnings,
        timestamp: startedAt
      )
    }
  }

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> {
    AsyncThrowingStream(ModelStreamPart.self) { continuation in
      Task {
        do {
          if request.tools.isEmpty == false {
            let response = try await generate(request)
            continuation.yield(.streamStart(warnings: response.warnings))
            emitResponseParts(response.content, continuation: continuation)
            continuation.yield(
              .finishStep(
                response: response.response,
                usage: response.usage,
                finishReason: response.finishReason,
                rawFinishReason: response.rawFinishReason,
                providerMetadata: response.providerMetadata
              )
            )
            continuation.yield(
              .finish(
                finishReason: response.finishReason,
                usage: response.usage,
                providerMetadata: response.providerMetadata
              )
            )
            continuation.finish()
            return
          }

          let prepared = try prepare(request)
          let session = try makeSession(prepared: prepared)
          let startedAt = Date()
          continuation.yield(.streamStart(warnings: prepared.warnings))

          switch prepared.responseMode {
          case .text:
            let stream = session.streamResponse(
              to: prepared.prompt.prompt,
              options: prepared.generationOptions
            )
            try await streamText(
              stream: stream,
              timestamp: startedAt,
              warnings: prepared.warnings,
              continuation: continuation
            )

          case .structured(let schema, let includeSchemaInPrompt):
            let stream = session.streamResponse(
              to: prepared.prompt.prompt,
              schema: schema,
              includeSchemaInPrompt: includeSchemaInPrompt,
              options: prepared.generationOptions
            )
            try await streamStructured(
              stream: stream,
              timestamp: startedAt,
              warnings: prepared.warnings,
              continuation: continuation
            )
          }

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  private func streamText(
    stream: LanguageModelSession.ResponseStream<String>,
    timestamp: Date,
    warnings: [CallWarning],
    continuation: AsyncThrowingStream<ModelStreamPart, Error>.Continuation
  ) async throws {
    let textID = UUID().uuidString
    var emittedStart = false
    var previous = ""

    for try await snapshot in stream {
      let current = snapshot.content
      if emittedStart == false {
        emittedStart = true
        continuation.yield(.textStart(id: textID))
      }

      let delta = appleDelta(previous: previous, current: current)
      if delta.isEmpty == false {
        continuation.yield(.textDelta(id: textID, text: delta))
      }
      previous = current
    }

    let response = try await stream.collect()
    let entries = Array(response.transcriptEntries)
    let toolCalls = appleToolCalls(from: entries)

    if toolCalls.isEmpty == false {
      for toolCall in toolCalls {
        continuation.yield(.toolCall(toolCall))
      }
      let metadata = LanguageModelResponseMetadata(
        id: appleResponseID(from: entries),
        modelID: id,
        timestamp: timestamp
      )
      continuation.yield(
        .finishStep(
          response: metadata,
          usage: .init(),
          finishReason: .toolCalls
        )
      )
      continuation.yield(.finish(finishReason: .toolCalls, usage: .init()))
      return
    }

    let fallbackText = response.content
    if emittedStart == false && fallbackText.isEmpty == false {
      continuation.yield(.textStart(id: textID))
      continuation.yield(.textDelta(id: textID, text: fallbackText))
      emittedStart = true
    }
    if emittedStart {
      continuation.yield(.textEnd(id: textID))
    }

    let metadata = LanguageModelResponseMetadata(
      id: appleResponseID(from: entries),
      modelID: id,
      timestamp: timestamp
    )
    continuation.yield(
      .finishStep(
        response: metadata,
        usage: .init(),
        finishReason: .stop
      )
    )
    continuation.yield(.finish(finishReason: .stop, usage: .init()))
  }

  private func streamStructured(
    stream: LanguageModelSession.ResponseStream<GeneratedContent>,
    timestamp: Date,
    warnings: [CallWarning],
    continuation: AsyncThrowingStream<ModelStreamPart, Error>.Continuation
  ) async throws {
    let textID = UUID().uuidString
    var emittedStart = false
    var previous = ""

    for try await snapshot in stream {
      let current = snapshot.rawContent.jsonString
      if emittedStart == false {
        emittedStart = true
        continuation.yield(.textStart(id: textID))
      }
      let delta = appleDelta(previous: previous, current: current)
      if delta.isEmpty == false {
        continuation.yield(.textDelta(id: textID, text: delta))
      }
      previous = current
    }

    let response = try await stream.collect()
    let entries = Array(response.transcriptEntries)
    let toolCalls = appleToolCalls(from: entries)

    if toolCalls.isEmpty == false {
      for toolCall in toolCalls {
        continuation.yield(.toolCall(toolCall))
      }
      let metadata = LanguageModelResponseMetadata(
        id: appleResponseID(from: entries),
        modelID: id,
        timestamp: timestamp
      )
      continuation.yield(
        .finishStep(
          response: metadata,
          usage: .init(),
          finishReason: .toolCalls
        )
      )
      continuation.yield(.finish(finishReason: .toolCalls, usage: .init()))
      return
    }

    let fallbackText = response.rawContent.jsonString
    if emittedStart == false && fallbackText.isEmpty == false {
      continuation.yield(.textStart(id: textID))
      continuation.yield(.textDelta(id: textID, text: fallbackText))
      emittedStart = true
    }
    if emittedStart {
      continuation.yield(.textEnd(id: textID))
    }

    let metadata = LanguageModelResponseMetadata(
      id: appleResponseID(from: entries),
      modelID: id,
      timestamp: timestamp
    )
    continuation.yield(
      .finishStep(
        response: metadata,
        usage: .init(),
        finishReason: .stop
      )
    )
    continuation.yield(.finish(finishReason: .stop, usage: .init()))
  }

  private func modelResponse(
    from entries: [Transcript.Entry],
    outputText: String,
    warnings: [CallWarning],
    timestamp: Date
  ) -> ModelResponse {
    let toolCalls = appleToolCalls(from: entries)
    let responseID = appleResponseID(from: entries)
    let hasToolCalls = toolCalls.isEmpty == false

    var content: [ModelContentPart] = []
    if hasToolCalls {
      content.append(contentsOf: toolCalls.map(ModelContentPart.toolCall))
    } else {
      let text = outputText.isEmpty ? appleResponseText(from: entries) : outputText
      if text.isEmpty == false {
        content.append(.text(text))
      }
    }

    return ModelResponse(
      content: content,
      finishReason: hasToolCalls ? .toolCalls : .stop,
      usage: .init(),
      warnings: warnings,
      request: .init(
        body: .object([
          "model": .string(id),
        ])
      ),
      response: .init(
        id: responseID,
        modelID: id,
        timestamp: timestamp
      )
    )
  }

  private func makeSession(prepared: ApplePreparedRequest) throws -> LanguageModelSession {
    let systemModel = SystemLanguageModel(useCase: settings.useCase, guardrails: settings.guardrails)
    switch systemModel.availability {
    case .available:
      break
    case .unavailable(let reason):
      throw AIKitError.invalidConfiguration(
        "Apple on-device language model is unavailable: \(availabilityReasonDescription(reason))."
      )
    @unknown default:
      throw AIKitError.invalidConfiguration("Apple on-device language model is unavailable.")
    }

    let tools: [any Tool] = prepared.tools.map { $0 }
    return LanguageModelSession(
      model: systemModel,
      tools: tools,
      instructions: prepared.prompt.instructions
    )
  }

  private func prepare(_ request: ModelRequest) throws -> ApplePreparedRequest {
    let includeSchemaInPrompt: Bool = {
      guard let appleOptions = request.providerOptions?["apple"],
            case let .bool(value)? = appleOptions["includeSchemaInPrompt"]
      else { return settings.includeSchemaInPrompt }
      return value
    }()

    var warnings: [CallWarning] = []
    let selectedToolsResult = selectTools(request: request)
    warnings.append(contentsOf: selectedToolsResult.warnings)

    var sessionTools: [AppleSessionTool] = []
    sessionTools.reserveCapacity(selectedToolsResult.tools.count)
    for tool in selectedToolsResult.tools {
      let schema = try appleGenerationSchema(from: tool.inputSchema, defaultName: tool.name)
      sessionTools.append(
        AppleSessionTool(
          name: tool.name,
          description: tool.description ?? "",
          parameters: schema,
          includesSchemaInInstructions: settings.includeToolSchemaInInstructions
        )
      )
    }

    let generationOptionsResult = buildGenerationOptions(from: request.settings)
    warnings.append(contentsOf: generationOptionsResult.warnings)

    let toolInstruction: String? = {
      guard selectedToolsResult.tools.isEmpty == false else { return nil }
      return appleToolChoiceInstruction(request.toolChoice, tools: selectedToolsResult.tools)
    }()
    let prompt = try applePreparePrompt(from: request.messages, toolChoiceInstruction: toolInstruction)

    let responseMode: AppleResponseMode
    switch request.responseFormat {
    case .text:
      responseMode = .text
    case .json:
      let schema = try GenerationSchema(
        root: .init(type: GeneratedContent.self),
        dependencies: []
      )
      responseMode = .structured(schema: schema, includeSchemaInPrompt: includeSchemaInPrompt)
    case .jsonSchema(let schema, let name, _):
      let defaultName = name ?? "response"
      let generationSchema = try appleGenerationSchema(from: schema, defaultName: defaultName)
      responseMode = .structured(schema: generationSchema, includeSchemaInPrompt: includeSchemaInPrompt)
    }

    return .init(
      prompt: prompt,
      responseMode: responseMode,
      generationOptions: generationOptionsResult.options,
      tools: sessionTools,
      warnings: warnings
    )
  }
}

private struct ApplePreparedRequest: Sendable {
  var prompt: ApplePreparedPrompt
  var responseMode: AppleResponseMode
  var generationOptions: GenerationOptions
  var tools: [AppleSessionTool]
  var warnings: [CallWarning]
}

private enum AppleResponseMode: Sendable {
  case text
  case structured(schema: GenerationSchema, includeSchemaInPrompt: Bool)
}

private struct AppleSessionTool: Tool {
  typealias Arguments = GeneratedContent
  typealias Output = String

  let name: String
  let description: String
  let parameters: GenerationSchema
  let includesSchemaInInstructions: Bool

  func call(arguments: GeneratedContent) async throws -> String {
    _ = arguments
    return ""
  }
}

struct AppleSelectedTools: Sendable {
  var tools: [ToolDefinition]
  var warnings: [CallWarning]
}

func selectTools(request: ModelRequest) -> AppleSelectedTools {
  switch request.toolChoice {
  case .none:
    return .init(tools: [], warnings: [])
  case .tool(let name):
    let selected = request.tools.filter { $0.name == name }
    if selected.isEmpty {
      return .init(
        tools: [],
        warnings: [
          .init(
            message: "Requested tool \"\(name)\" is not present in this request.",
            code: "unsupported-tool-choice"
          )
        ]
      )
    }
    return .init(tools: selected, warnings: [])
  case .auto:
    return .init(tools: request.tools, warnings: [])
  case .required:
    if request.tools.isEmpty {
      return .init(
        tools: [],
        warnings: [
          .init(
            message: "toolChoice.required has no tools available in this request.",
            code: "unsupported-tool-choice"
          )
        ]
      )
    }
    return .init(tools: request.tools, warnings: [])
  }
}

struct AppleGenerationOptionsResult: Sendable {
  var options: GenerationOptions
  var warnings: [CallWarning]
}

func buildGenerationOptions(from settings: CallSettings) -> AppleGenerationOptionsResult {
  var warnings: [CallWarning] = []
  var sampling: GenerationOptions.SamplingMode?

  let seed: UInt64? = {
    guard let seed = settings.seed else { return nil }
    guard seed >= 0 else {
      warnings.append(
        .init(
          message: "Negative seed values are unsupported by Apple on-device generation and will be ignored.",
          code: "unsupported-parameter"
        )
      )
      return nil
    }
    return UInt64(seed)
  }()

  if let topK = settings.topK {
    if topK > 0 {
      sampling = .random(top: topK, seed: seed)
    } else {
      warnings.append(
        .init(
          message: "topK must be greater than zero. Ignoring topK.",
          code: "unsupported-parameter"
        )
      )
    }
  } else if let topP = settings.topP {
    if (0...1).contains(topP) {
      sampling = .random(probabilityThreshold: topP, seed: seed)
    } else {
      warnings.append(
        .init(
          message: "topP must be between 0 and 1. Ignoring topP.",
          code: "unsupported-parameter"
        )
      )
    }
  } else if seed != nil {
    warnings.append(
      .init(
        message: "seed is only used when topK or topP sampling is configured.",
        code: "unsupported-parameter"
      )
    )
  }

  if settings.topK != nil && settings.topP != nil {
    warnings.append(
      .init(
        message: "Both topK and topP were provided. topP is ignored because topK takes precedence.",
        code: "unsupported-parameter"
      )
    )
  }

  if settings.presencePenalty != nil {
    warnings.append(
      .init(
        message: "presencePenalty is not supported by Apple on-device generation and will be ignored.",
        code: "unsupported-parameter"
      )
    )
  }
  if settings.frequencyPenalty != nil {
    warnings.append(
      .init(
        message: "frequencyPenalty is not supported by Apple on-device generation and will be ignored.",
        code: "unsupported-parameter"
      )
    )
  }
  if settings.stopSequences?.isEmpty == false {
    warnings.append(
      .init(
        message: "stopSequences are not supported by Apple on-device generation and will be ignored.",
        code: "unsupported-parameter"
      )
    )
  }

  return .init(
    options: .init(
      sampling: sampling,
      temperature: settings.temperature,
      maximumResponseTokens: settings.maxOutputTokens
    ),
    warnings: warnings
  )
}

private func emitResponseParts(
  _ content: [ModelContentPart],
  continuation: AsyncThrowingStream<ModelStreamPart, Error>.Continuation
) {
  let textID = UUID().uuidString
  var emittedText = false

  for part in content {
    switch part {
    case .text(let text, _):
      if emittedText == false {
        emittedText = true
        continuation.yield(.textStart(id: textID))
      }
      if text.isEmpty == false {
        continuation.yield(.textDelta(id: textID, text: text))
      }
    case .toolCall(let toolCall):
      continuation.yield(.toolCall(toolCall))
    case .reasoning, .toolApprovalRequest, .toolResult, .toolError, .toolOutputDenied, .source, .file:
      continue
    }
  }

  if emittedText {
    continuation.yield(.textEnd(id: textID))
  }
}

private func appleDelta(previous: String, current: String) -> String {
  if current.hasPrefix(previous) {
    return String(current.dropFirst(previous.count))
  }

  let prefixLength = zip(previous, current).prefix { $0 == $1 }.count
  return String(current.dropFirst(prefixLength))
}

private func availabilityReasonDescription(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
  switch reason {
  case .deviceNotEligible:
    return "device not eligible"
  case .appleIntelligenceNotEnabled:
    return "Apple Intelligence is not enabled"
  case .modelNotReady:
    return "model assets are not ready"
  @unknown default:
    return "unknown reason"
  }
}
