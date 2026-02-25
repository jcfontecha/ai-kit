import Foundation

public struct SpeechRequest: Sendable, Equatable {
  public var text: String

  public init(text: String) {
    self.text = text
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
