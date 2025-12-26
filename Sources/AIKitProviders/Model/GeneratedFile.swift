import Foundation

public struct GeneratedFile: Sendable, Equatable {
  public var data: Data
  public var mediaType: String

  public init(data: Data, mediaType: String) {
    self.data = data
    self.mediaType = mediaType
  }
}

