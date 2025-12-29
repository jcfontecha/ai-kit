import Foundation
import AIKitProviders

public struct AIClient: Sendable {
  public struct Defaults: Sendable {
    public var instructions: SystemPrompt?

    public var tools: ToolRegistry?
    public var toolChoice: ToolChoice
    public var activeTools: [String]?

    /// Convenience sugar over `stopWhen: [Stop.stepCountIs(maxSteps)]`.
    public var maxSteps: Int

    public var settings: CallSettings
    public var headers: [String: String]?
    public var providerOptions: ProviderOptions?
    public var maxRetries: Int
    public var cancellationToken: CancellationToken?
    public var download: DownloadFunction?

    public init(
      instructions: SystemPrompt? = nil,
      tools: ToolRegistry? = nil,
      toolChoice: ToolChoice = .auto,
      activeTools: [String]? = nil,
      maxSteps: Int = 1,
      settings: CallSettings = .init(),
      headers: [String: String]? = nil,
      providerOptions: ProviderOptions? = nil,
      maxRetries: Int = 2,
      cancellationToken: CancellationToken? = nil,
      download: DownloadFunction? = nil
    ) {
      self.instructions = instructions
      self.tools = tools
      self.toolChoice = toolChoice
      self.activeTools = activeTools
      self.maxSteps = maxSteps
      self.settings = settings
      self.headers = headers
      self.providerOptions = providerOptions
      self.maxRetries = maxRetries
      self.cancellationToken = cancellationToken
      self.download = download
    }
  }

  public var model: any LanguageModel
  public var defaults: Defaults

  public init(model: any LanguageModel, defaults: Defaults = .init()) {
    self.model = model
    self.defaults = defaults
  }

  public func generate(_ prompt: String) async throws -> GenerateTextResult<Output.Text> {
    try await generate(prompt, output: Output.text())
  }

  public func generate(messages: [ModelMessage]) async throws -> GenerateTextResult<Output.Text> {
    try await generate(messages: messages, output: Output.text())
  }

  public func generate<OUT: OutputSpec>(_ prompt: String, output: OUT) async throws -> GenerateTextResult<OUT> {
    try await generateText(
      model: model,
      system: defaults.instructions,
      prompt: prompt,
      tools: defaults.tools,
      toolChoice: defaults.toolChoice,
      activeTools: defaults.activeTools,
      settings: defaults.settings,
      headers: defaults.headers,
      providerOptions: defaults.providerOptions,
      maxRetries: defaults.maxRetries,
      cancellationToken: defaults.cancellationToken,
      download: defaults.download,
      stopWhen: [Stop.stepCountIs(max(defaults.maxSteps, 1))],
      output: output
    )
  }

  public func generate<OUT: OutputSpec>(messages: [ModelMessage], output: OUT) async throws -> GenerateTextResult<OUT> {
    try await generateText(
      model: model,
      system: defaults.instructions,
      messages: messages,
      tools: defaults.tools,
      toolChoice: defaults.toolChoice,
      activeTools: defaults.activeTools,
      settings: defaults.settings,
      headers: defaults.headers,
      providerOptions: defaults.providerOptions,
      maxRetries: defaults.maxRetries,
      cancellationToken: defaults.cancellationToken,
      download: defaults.download,
      stopWhen: [Stop.stepCountIs(max(defaults.maxSteps, 1))],
      output: output
    )
  }

  public func stream(_ prompt: String) -> StreamTextResult<Output.Text> {
    stream(prompt, output: Output.text())
  }

  public func stream(messages: [ModelMessage]) -> StreamTextResult<Output.Text> {
    stream(messages: messages, output: Output.text())
  }

  public func stream<OUT: OutputSpec>(_ prompt: String, output: OUT) -> StreamTextResult<OUT> {
    streamText(
      model: model,
      system: defaults.instructions,
      prompt: prompt,
      tools: defaults.tools,
      toolChoice: defaults.toolChoice,
      activeTools: defaults.activeTools,
      settings: defaults.settings,
      headers: defaults.headers,
      providerOptions: defaults.providerOptions,
      maxRetries: defaults.maxRetries,
      cancellationToken: defaults.cancellationToken,
      download: defaults.download,
      stopWhen: [Stop.stepCountIs(max(defaults.maxSteps, 1))],
      output: output
    )
  }

  public func stream<OUT: OutputSpec>(messages: [ModelMessage], output: OUT) -> StreamTextResult<OUT> {
    streamText(
      model: model,
      system: defaults.instructions,
      messages: messages,
      tools: defaults.tools,
      toolChoice: defaults.toolChoice,
      activeTools: defaults.activeTools,
      settings: defaults.settings,
      headers: defaults.headers,
      providerOptions: defaults.providerOptions,
      maxRetries: defaults.maxRetries,
      cancellationToken: defaults.cancellationToken,
      download: defaults.download,
      stopWhen: [Stop.stepCountIs(max(defaults.maxSteps, 1))],
      output: output
    )
  }
}

