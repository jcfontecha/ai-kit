import Foundation

public struct ModelStreamError: Sendable, Equatable {
  public var message: String
  public var type: String?
  public var code: JSONValue?
  public var param: JSONValue?
  public var providerMetadata: ProviderMetadata?

  public init(
    message: String,
    type: String? = nil,
    code: JSONValue? = nil,
    param: JSONValue? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.message = message
    self.type = type
    self.code = code
    self.param = param
    self.providerMetadata = providerMetadata
  }
}

public enum ModelStreamPart: Sendable, Equatable {
  case streamStart(warnings: [CallWarning] = [])
  case startStep(request: LanguageModelRequestMetadata = .init(), warnings: [CallWarning] = [])

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

  case responseMetadata(LanguageModelResponseMetadata)
  case finishStep(
    response: LanguageModelResponseMetadata = .init(),
    usage: Usage = .init(),
    finishReason: FinishReason,
    rawFinishReason: String? = nil,
    providerMetadata: ProviderMetadata? = nil
  )
  case finish(finishReason: FinishReason, usage: Usage = .init(), providerMetadata: ProviderMetadata? = nil)
  case raw(JSONValue)
  case error(ModelStreamError)
}
