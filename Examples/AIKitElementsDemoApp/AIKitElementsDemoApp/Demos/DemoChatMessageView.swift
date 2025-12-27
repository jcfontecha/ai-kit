import SwiftUI
import MarkdownUI

import AIKitCore
import AIKitProviders

struct DemoChatMessageView: View {
  let message: ChatMessage

  var body: some View {
    switch message.role {
    case .user:
      HStack {
        Spacer(minLength: 24)
        userBubble(text: messageText)
      }

    case .assistant:
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
          switch part {
          case .text(let text):
            Markdown(text.text)
              .frame(maxWidth: .infinity, alignment: .leading)
          case .reasoning(let reasoning):
            DisclosureGroup("Reasoning") {
              Markdown(reasoning.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
          default:
            EmptyView()
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

    case .system:
      Text(messageText)
        .font(.caption)
        .foregroundStyle(.secondary)

    case .tool:
      Text("Tool role message (unsupported in demo)")
        .font(.caption)
        .foregroundStyle(.secondary)

    @unknown default:
      Text("Unsupported message role: \(message.role.rawValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var messageText: String {
    message.parts.compactMap { part in
      guard case let .text(text) = part else { return nil }
      return text.text
    }.joined()
  }

  private func userBubble(text: String) -> some View {
    Text(text)
      .foregroundStyle(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.secondary.opacity(0.12))
      }
  }
}
