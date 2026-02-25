import Foundation

public protocol EmbeddingModel: Sendable {
  var id: String { get }
  func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResponse
}
