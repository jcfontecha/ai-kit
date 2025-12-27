import SwiftUI
import AIKitCore
import AIKitProviders
import AIKitElements

struct ConversationDemoView: View {
  @State private var items: [ChatMessage] = (1...30).map { index in
    ChatMessage(
      id: "demo.\(index)",
      role: index.isMultiple(of: 2) ? .assistant : .user,
      parts: [.text(.init(id: "demo.\(index).text", text: "Message \(index)", state: .done))]
    )
  }
  @State private var composerHeight: CGFloat = 120

  var body: some View {
    Conversation(messages: items, bottomOverlayHeight: composerHeight) { message in
      HStack {
        if message.role == .assistant {
          Text(messageText(message))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.12)))
          Spacer(minLength: 24)
        } else {
          Spacer(minLength: 24)
          Text(messageText(message))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
              RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            )
        }
      }
    }
    .overlay(alignment: .topTrailing) {
      Button("Add") {
        let next = items.count + 1
        items.append(
          ChatMessage(
            id: "demo.\(next)",
            role: next.isMultiple(of: 2) ? .assistant : .user,
            parts: [.text(.init(id: "demo.\(next).text", text: "Message \(next)", state: .done))]
          )
        )
      }
      .buttonStyle(.bordered)
      .padding(8)
    }
    .frame(height: 520)
  }

  private func messageText(_ message: ChatMessage) -> String {
    message.parts.compactMap { part in
      guard case let .text(text) = part else { return nil }
      return text.text
    }.joined()
  }
}
