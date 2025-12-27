import SwiftUI
import AIKitCore
import AIKitProviders
import AIKitElements

struct ConversationDemoView: View {
  @State private var items: [ChatMessage] = DemoContent.initialMessages

  var body: some View {
    Conversation(messages: items, bottomOverlayHeight: 0) { message in
      DemoChatMessageView(message: message)
        .id(message.id)
    }
    .overlay(alignment: .topTrailing) {
      Button("Reset") { items = DemoContent.initialMessages }
        .buttonStyle(.bordered)
        .padding(8)
    }
    .frame(height: 520)
  }
}
