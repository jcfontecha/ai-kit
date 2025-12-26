import Foundation

/// Response metadata for an image model call.
///
/// Mirrors the JS AI SDK `ImageModelResponseMetadata` shape.
public struct ImageModelResponseMetadata: Sendable, Equatable {
  public var timestamp: Date
  public var modelID: String
  public var headers: [String: String]?

  public init(
    timestamp: Date = Date(timeIntervalSince1970: 0),
    modelID: String = "",
    headers: [String: String]? = nil
  ) {
    self.timestamp = timestamp
    self.modelID = modelID
    self.headers = headers
  }
}
