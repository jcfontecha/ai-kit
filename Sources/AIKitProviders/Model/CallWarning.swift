import Foundation

/// Warning returned by a provider for a given call.
///
/// Providers can populate `code` and `metadata` when they have structured warnings.
public struct CallWarning: Sendable, Codable, Equatable {
  public var message: String
  public var code: String?
  public var metadata: JSONValue?

  public init(message: String, code: String? = nil, metadata: JSONValue? = nil) {
    self.message = message
    self.code = code
    self.metadata = metadata
  }
}

