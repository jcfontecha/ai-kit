import SwiftUI
import AIKitCore
import AIKitProviders
import AIKitElements

struct ConversationDemoView: View {
  @State private var items: [ChatMessage] = DemoContent.initialMessages

  var body: some View {
    Group {
      if items.isEmpty {
        ConversationEmptyState(
          title: "Start a conversation",
          description: "Messages will appear here as the conversation progresses.",
          icon: AnyView(Image(systemName: "message").font(.system(size: 36, weight: .regular)))
        )
      } else {
        Conversation(messages: items, bottomOverlayHeight: 0) { message in
          DemoChatMessageView(message: message)
        }
      }
    }
    .overlay(alignment: .topTrailing) {
      HStack(spacing: 8) {
        Button("Clear") { items = [] }
        Button("Reset") { items = DemoContent.initialMessages }
      }
      .buttonStyle(.bordered)
      .padding(8)
    }
    .frame(height: 520)
  }
}

