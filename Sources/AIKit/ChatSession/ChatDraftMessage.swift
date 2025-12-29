import Foundation
import AIKitProviders

public struct ChatDraftMessage: Sendable, Equatable {
  public var role: MessageRole
  public var parts: [ChatMessagePart]
  public var replaceMessageID: String?
  public var metadata: JSONValue?

  public init(
    role: MessageRole,
    parts: [ChatMessagePart],
    replaceMessageID: String? = nil,
    metadata: JSONValue? = nil
  ) {
    self.role = role
    self.parts = parts
    self.replaceMessageID = replaceMessageID
    self.metadata = metadata
  }
}

public struct ChatRequestOptions: Sendable, Equatable {
  public var headers: [String: String]?
  public var body: JSONValue?
  public var metadata: JSONValue?

  public init(
    headers: [String: String]? = nil,
    body: JSONValue? = nil,
    metadata: JSONValue? = nil
  ) {
    self.headers = headers
    self.body = body
    self.metadata = metadata
  }
}

