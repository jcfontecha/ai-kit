import Foundation

public struct TranscriptionRequest: Sendable, Equatable {
  public var audio: Data

  public init(audio: Data) {
    self.audio = audio
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
