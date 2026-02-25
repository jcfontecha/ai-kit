import SwiftUI
import AIKit

private struct ConversationEditUserMessageActionStore: @unchecked Sendable {
  var value: ((_ message: ChatMessage) -> Void)?
}

private struct ConversationOnEditUserMessageKey: EnvironmentKey {
  static let defaultValue = ConversationEditUserMessageActionStore(value: nil)
}

extension EnvironmentValues {
  var conversationOnEditUserMessage: ((_ message: ChatMessage) -> Void)? {
    get { self[ConversationOnEditUserMessageKey.self].value }
    set { self[ConversationOnEditUserMessageKey.self] = .init(value: newValue) }
  }
}

public extension View {
  func conversationOnEditUserMessage(_ handler: @escaping (_ message: ChatMessage) -> Void) -> some View {
    environment(\.conversationOnEditUserMessage, handler)
  }
}

