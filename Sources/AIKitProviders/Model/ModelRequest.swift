import Foundation

public struct ModelRequest: Sendable {
  public var messages: [ModelMessage]
  public var responseFormat: ResponseFormat
  public var tools: [ToolDefinition]
  public var toolChoice: ToolChoice
  public var settings: CallSettings
  public var headers: [String: String]?
  public var providerOptions: ProviderOptions?
  public var cancellationToken: CancellationToken?

  public init(
    messages: [ModelMessage],
    responseFormat: ResponseFormat = .text,
    tools: [ToolDefinition] = [],
    toolChoice: ToolChoice = .auto,
    settings: CallSettings = .init(),
    headers: [String: String]? = nil,
    providerOptions: ProviderOptions? = nil,
    cancellationToken: CancellationToken? = nil
  ) {
    self.messages = messages
    self.responseFormat = responseFormat
    self.tools = tools
    self.toolChoice = toolChoice
    self.settings = settings
    self.headers = headers
    self.providerOptions = providerOptions
    self.cancellationToken = cancellationToken
  }
}
