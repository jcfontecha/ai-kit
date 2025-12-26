import Foundation
import AIKitProviders

public protocol Agent: Sendable {
  associatedtype Output: OutputSpec
  func generate(prompt: String) async throws -> GenerateTextResult<Output>
  func stream(prompt: String) async -> StreamTextResult<Output>
}

public struct AgentCall<OUT: OutputSpec, CALL_OPTIONS: Sendable>: Sendable {
  public var prompt: String?
  public var messages: [ModelMessage]?
  public var options: CALL_OPTIONS?

  public var tools: ToolRegistry
  public var toolChoice: ToolChoice
  public var activeTools: [String]?
  public var stopWhen: [StopCondition]
  public var output: OUT
  public var system: SystemPrompt?
  public var settings: CallSettings
  public var headers: [String: String]?
  public var providerOptions: ProviderOptions?
  public var download: DownloadFunction?
  public var experimentalContext: AnySendable?

  public init(
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    options: CALL_OPTIONS? = nil,
    tools: ToolRegistry,
    toolChoice: ToolChoice,
    activeTools: [String]?,
    stopWhen: [StopCondition],
    output: OUT,
    system: SystemPrompt? = nil,
    settings: CallSettings = .init(),
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    download: DownloadFunction? = nil,
    experimentalContext: AnySendable? = nil
  ) {
    self.prompt = prompt
    self.messages = messages
    self.options = options
    self.tools = tools
    self.toolChoice = toolChoice
    self.activeTools = activeTools
    self.stopWhen = stopWhen
    self.output = output
    self.system = system
    self.settings = settings
    self.headers = headers
    self.providerOptions = providerOptions
    self.download = download
    self.experimentalContext = experimentalContext
  }
}

public struct ToolLoopAgent<CALL_OPTIONS: Sendable, OUT: OutputSpec>: Agent {
  public typealias Output = OUT
  public var id: String?
  public var model: any LanguageModel
  public var instructions: SystemPrompt?
  public var tools: ToolRegistry

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
  public var prepareCall: (@Sendable (AgentCall<OUT, CALL_OPTIONS>) async -> AgentCall<OUT, CALL_OPTIONS>)?

  public init(
    id: String? = nil,
    model: any LanguageModel,
    instructions: SystemPrompt? = nil,
    tools: ToolRegistry = .init(),
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
    stopWhen: [StopCondition] = [Stop.stepCountIs(20)],
    output: OUT,
    prepareCall: (@Sendable (AgentCall<OUT, CALL_OPTIONS>) async -> AgentCall<OUT, CALL_OPTIONS>)? = nil
  ) {
    self.id = id
    self.model = model
    self.instructions = instructions
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
    self.prepareCall = prepareCall
  }

  public func generate(prompt: String) async throws -> GenerateTextResult<OUT> {
    try await generate(prompt: prompt, options: nil)
  }

  public func generate(prompt: String, options: CALL_OPTIONS? = nil) async throws -> GenerateTextResult<OUT> {
    let call = await prepareCall(AgentCall(
      prompt: prompt,
      messages: nil,
      options: options,
      tools: tools,
      toolChoice: toolChoice,
      activeTools: activeTools,
      stopWhen: stopWhen,
      output: output,
      system: instructions,
      settings: settings,
      headers: headers,
      providerOptions: providerOptions,
      download: download,
      experimentalContext: nil
    ))
    return try await generateText(.init(
      model: model,
      system: call.system,
      prompt: call.prompt,
      messages: call.messages,
      tools: call.tools,
      toolChoice: call.toolChoice,
      activeTools: call.activeTools,
      settings: call.settings,
      headers: call.headers,
      providerOptions: call.providerOptions,
      maxRetries: maxRetries,
      cancellationToken: cancellationToken,
      prepareStep: prepareStep,
      repairToolCall: repairToolCall,
      download: call.download,
      stopWhen: call.stopWhen,
      output: call.output,
      experimentalContext: call.experimentalContext
    ))
  }

  public func stream(prompt: String) async -> StreamTextResult<OUT> {
    await stream(prompt: prompt, options: nil)
  }

  public func stream(prompt: String, options: CALL_OPTIONS? = nil) async -> StreamTextResult<OUT> {
    let call = await prepareCall(AgentCall(
      prompt: prompt,
      messages: nil,
      options: options,
      tools: tools,
      toolChoice: toolChoice,
      activeTools: activeTools,
      stopWhen: stopWhen,
      output: output,
      system: instructions,
      settings: settings,
      headers: headers,
      providerOptions: providerOptions,
      download: download,
      experimentalContext: nil
    ))
    return streamText(.init(
      model: model,
      system: call.system,
      prompt: call.prompt,
      messages: call.messages,
      tools: call.tools,
      toolChoice: call.toolChoice,
      activeTools: call.activeTools,
      settings: call.settings,
      headers: call.headers,
      providerOptions: call.providerOptions,
      maxRetries: maxRetries,
      cancellationToken: cancellationToken,
      prepareStep: prepareStep,
      repairToolCall: repairToolCall,
      download: call.download,
      stopWhen: call.stopWhen,
      output: call.output,
      experimentalContext: call.experimentalContext
    ))
  }

  public func generate(messages: [ModelMessage], options: CALL_OPTIONS? = nil) async throws -> GenerateTextResult<OUT> {
    let call = await prepareCall(AgentCall(
      prompt: nil,
      messages: messages,
      options: options,
      tools: tools,
      toolChoice: toolChoice,
      activeTools: activeTools,
      stopWhen: stopWhen,
      output: output,
      system: instructions,
      settings: settings,
      headers: headers,
      providerOptions: providerOptions,
      download: download,
      experimentalContext: nil
    ))
    return try await generateText(.init(
      model: model,
      system: call.system,
      prompt: call.prompt,
      messages: call.messages,
      tools: call.tools,
      toolChoice: call.toolChoice,
      activeTools: call.activeTools,
      settings: call.settings,
      headers: call.headers,
      providerOptions: call.providerOptions,
      maxRetries: maxRetries,
      cancellationToken: cancellationToken,
      prepareStep: prepareStep,
      repairToolCall: repairToolCall,
      download: call.download,
      stopWhen: call.stopWhen,
      output: call.output,
      experimentalContext: call.experimentalContext
    ))
  }

  public func stream(messages: [ModelMessage], options: CALL_OPTIONS? = nil) async -> StreamTextResult<OUT> {
    let call = await prepareCall(AgentCall(
      prompt: nil,
      messages: messages,
      options: options,
      tools: tools,
      toolChoice: toolChoice,
      activeTools: activeTools,
      stopWhen: stopWhen,
      output: output,
      system: instructions,
      settings: settings,
      headers: headers,
      providerOptions: providerOptions,
      download: download,
      experimentalContext: nil
    ))
    return streamText(.init(
      model: model,
      system: call.system,
      prompt: call.prompt,
      messages: call.messages,
      tools: call.tools,
      toolChoice: call.toolChoice,
      activeTools: call.activeTools,
      settings: call.settings,
      headers: call.headers,
      providerOptions: call.providerOptions,
      maxRetries: maxRetries,
      cancellationToken: cancellationToken,
      prepareStep: prepareStep,
      repairToolCall: repairToolCall,
      download: call.download,
      stopWhen: call.stopWhen,
      output: call.output,
      experimentalContext: call.experimentalContext
    ))
  }

  private func prepareCall(_ call: AgentCall<OUT, CALL_OPTIONS>) async -> AgentCall<OUT, CALL_OPTIONS> {
    await prepareCall?(call) ?? call
  }
}
