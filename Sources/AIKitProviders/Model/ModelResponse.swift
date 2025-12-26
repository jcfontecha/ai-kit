import Foundation

public enum ModelContentPart: Sendable, Equatable {
  case text(String, metadata: ProviderMetadata? = nil)
  case reasoning(String, metadata: ProviderMetadata? = nil)
  case toolCall(ToolCall)
  case toolApprovalRequest(ToolApprovalRequest)
  case toolResult(ToolResult)
  case toolError(ToolError)
  case toolOutputDenied(ToolOutputDenied)
  case source(Source)
  case file(GeneratedFile)
}

public struct ModelResponse: Sendable, Equatable {
  public var content: [ModelContentPart]
  public var finishReason: FinishReason
  public var rawFinishReason: String?
  public var usage: Usage
  public var warnings: [CallWarning]
  public var request: LanguageModelRequestMetadata
  public var response: LanguageModelResponseMetadata
  public var providerMetadata: ProviderMetadata?

  public init(
    content: [ModelContentPart],
    finishReason: FinishReason,
    rawFinishReason: String? = nil,
    usage: Usage = .init(),
    warnings: [CallWarning] = [],
    request: LanguageModelRequestMetadata = .init(),
    response: LanguageModelResponseMetadata = .init(),
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.content = content
    self.finishReason = finishReason
    self.rawFinishReason = rawFinishReason
    self.usage = usage
    self.warnings = warnings
    self.request = request
    self.response = response
    self.providerMetadata = providerMetadata
  }
}
