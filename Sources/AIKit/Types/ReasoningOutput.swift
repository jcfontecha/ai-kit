import Foundation
import AIKitProviders

public struct ReasoningOutput: Sendable, Equatable {
  public var text: String
  public var providerMetadata: ProviderMetadata?

  public init(text: String, providerMetadata: ProviderMetadata? = nil) {
    self.text = text
    self.providerMetadata = providerMetadata
  }
}

