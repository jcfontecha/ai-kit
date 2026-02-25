import Foundation
import AIKitProviders

public struct NoObjectGeneratedError: Error, Sendable, Equatable {
  public var message: String
  public var finishReason: FinishReason
  public var usage: Usage
  public var response: LanguageModelResponseMetadata?

  public init(
    message: String,
    finishReason: FinishReason,
    usage: Usage,
    response: LanguageModelResponseMetadata? = nil
  ) {
    self.message = message
    self.finishReason = finishReason
    self.usage = usage
    self.response = response
  }
}

