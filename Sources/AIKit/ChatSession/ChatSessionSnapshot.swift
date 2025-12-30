import Foundation

struct ChatSessionSnapshot: Sendable, Equatable {
  var status: ChatStatus
  var messages: [ChatMessage]
  var errorDescription: String?

  init(
    status: ChatStatus,
    messages: [ChatMessage],
    errorDescription: String?
  ) {
    self.status = status
    self.messages = messages
    self.errorDescription = errorDescription
  }
}
