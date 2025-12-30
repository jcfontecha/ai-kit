import SwiftUI

private struct ConversationBottomOverlayHeightKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

private struct ConversationShowsScrollButtonKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

public extension EnvironmentValues {
  var conversationBottomOverlayHeight: CGFloat {
    get { self[ConversationBottomOverlayHeightKey.self] }
    set { self[ConversationBottomOverlayHeightKey.self] = newValue }
  }

  var conversationShowsScrollButton: Bool {
    get { self[ConversationShowsScrollButtonKey.self] }
    set { self[ConversationShowsScrollButtonKey.self] = newValue }
  }
}

public extension View {
  func conversationBottomOverlayHeight(_ height: CGFloat) -> some View {
    environment(\.conversationBottomOverlayHeight, height)
  }

  func conversationShowsScrollToLatestButton(_ shows: Bool) -> some View {
    environment(\.conversationShowsScrollButton, shows)
  }
}

