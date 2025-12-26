import Foundation

public struct LanguageModelRequestMetadata: Sendable, Equatable {
  /// Request HTTP body that was sent to the provider API.
  public var body: JSONValue?

  public init(body: JSONValue? = nil) {
    self.body = body
  }
}

public struct LanguageModelResponseMetadata: Sendable, Equatable {
  /// ID for the generated response.
  public var id: String
  /// The ID of the response model that was used to generate the response.
  public var modelID: String
  /// Timestamp for the start of the generated response.
  public var timestamp: Date
  public var headers: [String: String]?
  /// Response body (available only for providers that use HTTP requests).
  public var body: JSONValue?

  public init(
    id: String = "",
    modelID: String = "",
    timestamp: Date = Date(timeIntervalSince1970: 0),
    headers: [String: String]? = nil,
    body: JSONValue? = nil
  ) {
    self.id = id
    self.modelID = modelID
    self.timestamp = timestamp
    self.headers = headers
    self.body = body
  }
}
