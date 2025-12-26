import Foundation
import AIKitProviders

public struct NoImageGeneratedError: Error, Sendable, Equatable {
  public var message: String
  public var responses: [ImageModelResponseMetadata]?

  public init(
    message: String = "No image generated.",
    responses: [ImageModelResponseMetadata]? = nil
  ) {
    self.message = message
    self.responses = responses
  }
}

