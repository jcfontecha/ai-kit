import SwiftUI

// Internal bridge between `Conversation` (child) and `ChatComposerModifier` (parent):
// - Preference flows up: whether the conversation is "at latest" (to show/hide the arrow).
// - Environment flows down: a trigger the parent can bump to request a programmatic scroll-to-latest.

struct ConversationIsAtLatestForScrollButtonPreferenceKey: PreferenceKey {
  static let defaultValue: Bool = true
  static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = nextValue()
  }
}

private struct ConversationScrollToLatestRequestKey: EnvironmentKey {
  static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
  var conversationScrollToLatestRequest: Binding<Int> {
    get { self[ConversationScrollToLatestRequestKey.self] }
    set { self[ConversationScrollToLatestRequestKey.self] = newValue }
  }
}

extension View {
  func conversationScrollToLatestRequest(_ request: Binding<Int>) -> some View {
    environment(\.conversationScrollToLatestRequest, request)
  }
}

