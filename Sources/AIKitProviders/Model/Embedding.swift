import Foundation

public struct EmbeddingRequest: Sendable, Equatable {
  public var input: [String]

  public init(input: [String]) {
    self.input = input
  }
}

public struct EmbeddingResponse: Sendable, Equatable {
  public var vectors: [[Double]]
  public var modelID: String?
  public var usage: Usage?
  public var providerMetadata: ProviderMetadata?

  public init(
    vectors: [[Double]],
    modelID: String? = nil,
    usage: Usage? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.vectors = vectors
    self.modelID = modelID
    self.usage = usage
    self.providerMetadata = providerMetadata
  }
}
