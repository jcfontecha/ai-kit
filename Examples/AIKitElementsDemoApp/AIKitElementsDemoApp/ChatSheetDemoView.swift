import SwiftUI
import Foundation
import AIKit
import AIKitElements

struct ChatSheetDemoView: View {
  @State private var isPresented: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Chat in a resizable sheet")
        .font(.headline)

      Text("This demo presents a chat conversation in a sheet with detents. The conversation should scroll at the medium detent, rather than resizing the sheet on scroll gestures.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Button("Present sheet") { isPresented = true }
        .buttonStyle(.borderedProminent)

      Spacer()
    }
    .padding(16)
    .sheet(isPresented: $isPresented) {
      SheetChatConversationView()
        .chatSheetDefaults()
    }
  }
}

private struct SheetChatConversationView: View {
  @State private var messages: [ChatMessage] = DemoContent.performanceMessages
  @State private var text: String = ""

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Conversation(messages: messages, status: .ready)
        .conversationAnchorsNewUserMessagesToTop(true)
        .chatComposer(
          text: $text,
          status: .ready,
          showsScrollToLatestButton: true,
          onSend: { message in
            let messageID = UUID().uuidString
            messages.append(ChatMessage(
              id: messageID,
              role: .user,
              parts: [
                .text(.init(id: "\(messageID).text", text: message, state: .done))
              ]
            ))
            text = ""
          },
          onStop: {}
        )
        .navigationTitle("Chat Sheet")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
          }
        }
#else
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button("Done") { dismiss() }
          }
        }
#endif
    }
  }
}
