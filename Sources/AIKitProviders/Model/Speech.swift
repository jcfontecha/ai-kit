import Foundation

public struct SpeechRequest: Sendable, Equatable {
  public var text: String
  public var providerOptions: ProviderOptions?

  public init(
    text: String,
    providerOptions: ProviderOptions? = nil
  ) {
    self.text = text
    self.providerOptions = providerOptions
  }
}

public struct SpeechResponse: Sendable, Equatable {
  public var audio: Data
  public var modelID: String?

  public init(audio: Data, modelID: String? = nil) {
    self.audio = audio
    self.modelID = modelID
  }
}
