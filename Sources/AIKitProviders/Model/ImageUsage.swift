import Foundation

/// Token usage information for an image model call.
///
/// Mirrors the JS AI SDK `ImageModelUsage` shape: `inputTokens`, `outputTokens`, `totalTokens`.
public struct ImageUsage: Sendable, Codable, Equatable {
  public var inputTokens: Int?
  public var outputTokens: Int?
  public var totalTokens: Int?

  public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.totalTokens = totalTokens
  }
}

