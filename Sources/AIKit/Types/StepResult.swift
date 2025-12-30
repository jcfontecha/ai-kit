import Foundation
import AIKitProviders

public struct StepResult: Sendable, Equatable {
  public var content: [ContentPart]

  public var finishReason: FinishReason
  public var rawFinishReason: String?

  public var usage: Usage
  public var warnings: [CallWarning]

  public var request: LanguageModelRequestMetadata
  public var response: LanguageModelResponseMetadata
  /// Messages produced by this step (assistant + optional tool message).
  public var responseMessages: [ModelMessage]
  public var providerMetadata: ProviderMetadata?

  public init(
    content: [ContentPart],
    finishReason: FinishReason,
    rawFinishReason: String? = nil,
    usage: Usage = .init(),
    warnings: [CallWarning] = [],
    request: LanguageModelRequestMetadata = .init(),
    response: LanguageModelResponseMetadata = .init(),
    responseMessages: [ModelMessage] = [],
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.content = content
    self.finishReason = finishReason
    self.rawFinishReason = rawFinishReason
    self.usage = usage
    self.warnings = warnings
    self.request = request
    self.response = response
    self.responseMessages = responseMessages
    self.providerMetadata = providerMetadata
  }

  public var text: String {
    content.compactMap { part in
      if case let .text(text, _) = part { return text }
      return nil
    }.joined()
  }

  public var toolCalls: [ToolCall] {
    content.compactMap { part in
      if case let .toolCall(call) = part { return call }
      return nil
    }
  }

  public var toolResults: [ToolResult] {
    content.compactMap { part in
      if case let .toolResult(result) = part { return result }
      return nil
    }
  }
}
