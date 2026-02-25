import SwiftUI

private struct ConversationBottomOverlayHeightKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

private struct ConversationShowsScrollButtonKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

private struct ConversationAnchorsNewUserMessagesToTopKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

private struct ConversationDebugOverlayEnabledKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

private struct ConversationTopOverlayHeightKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
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

  /// When enabled, sending a new `.user` message scrolls that message to the top of the viewport, leaving space
  /// for the assistant response to stream in below. Once the streamed response overflows, the conversation
  /// switches back to stick-to-bottom behavior.
  var conversationAnchorsNewUserMessagesToTop: Bool {
    get { self[ConversationAnchorsNewUserMessagesToTopKey.self] }
    set { self[ConversationAnchorsNewUserMessagesToTopKey.self] = newValue }
  }

  /// Debug-only overlay for inspecting/copying scroll state.
  var conversationDebugOverlayEnabled: Bool {
    get { self[ConversationDebugOverlayEnabledKey.self] }
    set { self[ConversationDebugOverlayEnabledKey.self] = newValue }
  }

  /// Height of any top overlay that visually covers the Conversation scroll viewport (e.g. a custom nav header).
  /// Used to align the newest user message right below that overlay when `conversationAnchorsNewUserMessagesToTop`
  /// is enabled.
  var conversationTopOverlayHeight: CGFloat {
    get { self[ConversationTopOverlayHeightKey.self] }
    set { self[ConversationTopOverlayHeightKey.self] = newValue }
  }
}

public extension View {
  func conversationBottomOverlayHeight(_ height: CGFloat) -> some View {
    environment(\.conversationBottomOverlayHeight, height)
  }

  func conversationShowsScrollToLatestButton(_ shows: Bool) -> some View {
    environment(\.conversationShowsScrollButton, shows)
  }

  func conversationAnchorsNewUserMessagesToTop(_ enabled: Bool) -> some View {
    environment(\.conversationAnchorsNewUserMessagesToTop, enabled)
  }

  func conversationDebugOverlayEnabled(_ enabled: Bool) -> some View {
    environment(\.conversationDebugOverlayEnabled, enabled)
  }

  func conversationTopOverlayHeight(_ height: CGFloat) -> some View {
    environment(\.conversationTopOverlayHeight, height)
  }
}
