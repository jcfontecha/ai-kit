import Foundation

public enum SourceType: String, Sendable, Codable, Equatable {
  case url
}

public struct Source: Sendable, Equatable {
  public var sourceType: SourceType
  public var id: String
  public var url: String
  public var title: String?
  public var providerMetadata: ProviderMetadata?

  public init(
    sourceType: SourceType = .url,
    id: String,
    url: String,
    title: String? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.sourceType = sourceType
    self.id = id
    self.url = url
    self.title = title
    self.providerMetadata = providerMetadata
  }
}

