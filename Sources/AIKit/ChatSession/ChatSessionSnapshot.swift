import Foundation

public struct ChatSessionSnapshot: Sendable, Equatable {
  public var status: ChatSessionStatus
  public var messages: [ChatMessage]
  public var errorDescription: String?

  public init(
    status: ChatSessionStatus,
    messages: [ChatMessage],
    errorDescription: String?
  ) {
    self.status = status
    self.messages = messages
    self.errorDescription = errorDescription
  }
}

