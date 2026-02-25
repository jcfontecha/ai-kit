import Foundation

public protocol LanguageModel: Sendable {
  var id: String { get }
  var capabilities: ModelCapabilities { get }
  var supportedURLs: SupportedURLPatterns { get }

  func generate(_ request: ModelRequest) async throws -> ModelResponse
  func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error>
}
