import Foundation

public struct TranscriptionRequest: Sendable, Equatable {
  public var audio: Data
  public var mediaType: String?
  public var providerOptions: ProviderOptions?

  public init(
    audio: Data,
    mediaType: String? = nil,
    providerOptions: ProviderOptions? = nil
  ) {
    self.audio = audio
    self.mediaType = mediaType
    self.providerOptions = providerOptions
  }
}

public struct TranscriptionResponse: Sendable, Equatable {
  public var text: String
  public var modelID: String?

  public init(text: String, modelID: String? = nil) {
    self.text = text
    self.modelID = modelID
  }
}
