@_exported import AIKitProviders
@_spi(Advanced) import AIKitCore

// MARK: - Curated re-exports (AIKit is the public surface)

public typealias AIClient = AIKitCore.AIClient

// Agent + core generation
public typealias Agent = AIKitCore.Agent
public typealias AgentCall = AIKitCore.AgentCall
public typealias ToolLoopAgent = AIKitCore.ToolLoopAgent
public typealias GenerateTextOptions = AIKitCore.GenerateTextOptions
public typealias GenerateTextResult = AIKitCore.GenerateTextResult
public typealias GenerateTextFinishEvent = AIKitCore.GenerateTextFinishEvent
public typealias StreamTextOptions = AIKitCore.StreamTextOptions
public typealias StreamTextResult = AIKitCore.StreamTextResult
public typealias StreamTextFinishEvent = AIKitCore.StreamTextFinishEvent
public typealias StreamTextTransform = AIKitCore.StreamTextTransform
public typealias TextStreamPart = AIKitCore.TextStreamPart
public typealias GenerateImagePrompt = AIKitCore.GenerateImagePrompt
public typealias GenerateImageOptions = AIKitCore.GenerateImageOptions
public typealias GenerateImageResult = AIKitCore.GenerateImageResult
public typealias PrepareStepContext = AIKitCore.PrepareStepContext
public typealias PrepareStepFunction = AIKitCore.PrepareStepFunction
public typealias PrepareStepResult = AIKitCore.PrepareStepResult
public typealias StopCondition = AIKitCore.StopCondition
public typealias Stop = AIKitCore.Stop
public typealias StepResult = AIKitCore.StepResult
public typealias ContentPart = AIKitCore.ContentPart
public typealias ReasoningOutput = AIKitCore.ReasoningOutput

// Output + schema
public typealias OutputSpec = AIKitCore.OutputSpec
public typealias OutputContext = AIKitCore.OutputContext
public typealias Output = AIKitCore.Output
public typealias ObjectSchema = AIKitCore.ObjectSchema
public typealias SchemaProviding = AIKitCore.SchemaProviding

/// Canonical JSON value type used across AIKit APIs.
///
/// Use `AIKit.JSONValue` to disambiguate with app-level `JSONValue` types.
public typealias JSONValue = AIKitProviders.JSONValue

// Chat
public typealias ChatMessage = AIKitCore.ChatMessage
public typealias ChatMessagePart = AIKitCore.ChatMessagePart
public typealias ChatTextPart = AIKitCore.ChatTextPart
public typealias ChatReasoningPart = AIKitCore.ChatReasoningPart
public typealias ChatSourceURLPart = AIKitCore.ChatSourceURLPart
public typealias ChatSourceDocumentPart = AIKitCore.ChatSourceDocumentPart
public typealias ChatDataPart = AIKitCore.ChatDataPart
public typealias ChatFilePart = AIKitCore.ChatFilePart
public typealias ChatToolPart = AIKitCore.ChatToolPart
public typealias ChatDraftMessage = AIKitCore.ChatDraftMessage
public typealias ChatRequestOptions = AIKitCore.ChatRequestOptions
public typealias ChatSessionStatus = AIKitCore.ChatSessionStatus
public typealias ChatSessionSnapshot = AIKitCore.ChatSessionSnapshot

// Tools
public typealias AnySendable = AIKitCore.AnySendable
public typealias ToolID = AIKitCore.ToolID
public typealias ToolContext = AIKitCore.ToolContext
public typealias ToolKind = AIKitCore.ToolKind
public typealias ToolNeedsApproval = AIKitCore.ToolNeedsApproval
public typealias ToolProgress = AIKitCore.ToolProgress
public typealias ToolExecution = AIKitCore.ToolExecution
public typealias ToolSpec = AIKitCore.ToolSpec
public typealias SystemPrompt = AIKitCore.SystemPrompt
public typealias ToolRegistry = AIKitCore.ToolRegistry
public typealias ToolChoice = AIKitProviders.ToolChoice

// Tool call repair
public typealias ToolCallRepairError = AIKitCore.ToolCallRepairError
public typealias ToolCallRepairContext = AIKitCore.ToolCallRepairContext
public typealias ToolCallRepairFunction = AIKitCore.ToolCallRepairFunction

// Errors
public typealias AIKitError = AIKitCore.AIKitError
public typealias NoObjectGeneratedError = AIKitCore.NoObjectGeneratedError
public typealias NoImageGeneratedError = AIKitCore.NoImageGeneratedError
public typealias NoSuchToolError = AIKitCore.NoSuchToolError
public typealias InvalidToolInputError = AIKitCore.InvalidToolInputError
public typealias ToolCallRepairFailedError = AIKitCore.ToolCallRepairFailedError
public typealias ToolCallError = AIKitCore.ToolCallError


// MARK: - Function forwarders (keep AIKit as the only import)

@_spi(Advanced)
public func generateText<OUT: OutputSpec>(_ options: GenerateTextOptions<OUT>) async throws -> GenerateTextResult<OUT> {
  try await AIKitCore.generateText(options)
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
  try await AIKitCore.generateText(
    model: model,
    system: system,
    prompt: prompt,
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
  )
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
  try await AIKitCore.generateText(
    model: model,
    system: system,
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
  )
}

@_spi(Advanced)
public func streamText<OUT: OutputSpec>(_ options: StreamTextOptions<OUT>) -> StreamTextResult<OUT> {
  AIKitCore.streamText(options)
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
  AIKitCore.streamText(
    model: model,
    system: system,
    prompt: prompt,
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
  )
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
  AIKitCore.streamText(
    model: model,
    system: system,
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
  )
}

public func generateImage(_ options: GenerateImageOptions) async throws -> GenerateImageResult {
  try await AIKitCore.generateImage(options)
}

public func generateImage(
  model: any ImageModel,
  prompt: GenerateImagePrompt,
  n: Int = 1,
  maxImagesPerCall: Int? = nil,
  size: String? = nil,
  aspectRatio: String? = nil,
  seed: Int? = nil,
  providerOptions: ProviderOptions? = nil,
  headers: [String: String]? = nil,
  maxRetries: Int = 2,
  cancellationToken: CancellationToken? = nil
) async throws -> GenerateImageResult {
  try await AIKitCore.generateImage(
    model: model,
    prompt: prompt,
    n: n,
    maxImagesPerCall: maxImagesPerCall,
    size: size,
    aspectRatio: aspectRatio,
    seed: seed,
    providerOptions: providerOptions,
    headers: headers,
    maxRetries: maxRetries,
    cancellationToken: cancellationToken
  )
}
